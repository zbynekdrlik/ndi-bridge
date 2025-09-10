#!/usr/bin/env python3
"""
Test to verify that ALL test directories are properly discovered by pytest.
This prevents accidentally excluding test directories from the main test suite.
"""

import os
import subprocess
import pytest
from pathlib import Path


def test_all_test_directories_are_discovered():
    """
    Verify that pytest discovers tests in ALL subdirectories that contain test files.
    This prevents the issue where test directories are accidentally excluded.
    """
    # Get the tests root directory
    tests_root = Path(__file__).parent
    
    # Find all directories containing test_*.py files
    test_directories = set()
    for root, dirs, files in os.walk(tests_root):
        # Skip __pycache__ directories
        if '__pycache__' in root:
            continue
        # Check if directory contains test files
        if any(f.startswith('test_') and f.endswith('.py') for f in files):
            # Get relative path from tests root
            rel_path = Path(root).relative_to(tests_root)
            if str(rel_path) != '.':  # Skip root directory itself
                # Get the first level subdirectory (component, integration, etc.)
                parts = rel_path.parts
                if len(parts) >= 2:  # e.g., component/network
                    test_directories.add(f"{parts[0]}/{parts[1]}")
    
    # Collect tests from the full suite
    result = subprocess.run(
        ['python3', '-m', 'pytest', '--collect-only', '-q', str(tests_root)],
        capture_output=True,
        text=True
    )
    
    # Count tests collected from full suite
    full_suite_count = 0
    for line in result.stdout.split('\n'):
        if 'tests collected' in line:
            full_suite_count = int(line.split()[0])
            break
    
    # Collect tests from each directory individually
    total_individual_count = 0
    missing_directories = []
    
    for test_dir in sorted(test_directories):
        dir_path = tests_root / test_dir
        if dir_path.exists():
            # Check if __init__.py exists
            init_file = dir_path / '__init__.py'
            if not init_file.exists():
                print(f"WARNING: {test_dir} is missing __init__.py file!")
                missing_directories.append(test_dir)
            
            # Count tests in this directory
            result = subprocess.run(
                ['python3', '-m', 'pytest', '--collect-only', '-q', str(dir_path)],
                capture_output=True,
                text=True
            )
            for line in result.stdout.split('\n'):
                if 'tests collected' in line:
                    count = int(line.split()[0])
                    total_individual_count += count
                    print(f"  {test_dir}: {count} tests")
                    break
    
    # Also count tests in root level test files
    root_test_files = [f for f in os.listdir(tests_root) 
                       if f.startswith('test_') and f.endswith('.py')]
    if root_test_files:
        for test_file in root_test_files:
            result = subprocess.run(
                ['python3', '-m', 'pytest', '--collect-only', '-q', 
                 str(tests_root / test_file)],
                capture_output=True,
                text=True
            )
            for line in result.stdout.split('\n'):
                if 'tests collected' in line:
                    count = int(line.split()[0])
                    total_individual_count += count
                    print(f"  {test_file}: {count} tests")
                    break
    
    print(f"\nTotal tests when collected individually: {total_individual_count}")
    print(f"Total tests in full suite: {full_suite_count}")
    
    # Check if any directories are missing __init__.py
    assert len(missing_directories) == 0, \
        f"The following test directories are missing __init__.py files: {missing_directories}"
    
    # Check if all tests are included
    assert full_suite_count >= total_individual_count, \
        f"Full suite is missing tests! Individual: {total_individual_count}, Suite: {full_suite_count}"
    
    print("✓ All test directories are properly included in the main test suite")


def test_no_test_directories_excluded_in_pytest_config():
    """
    Verify that pytest.ini doesn't exclude any test directories.
    """
    tests_root = Path(__file__).parent
    pytest_ini = tests_root / 'pytest.ini'
    
    if pytest_ini.exists():
        with open(pytest_ini) as f:
            content = f.read()
            
        # Check for common exclusion patterns
        problematic_patterns = [
            'ignore =',
            'ignore_paths =',
            '--ignore=',
            'norecursedirs.*tests',  # Should not exclude tests subdirs
        ]
        
        for pattern in problematic_patterns:
            assert pattern not in content.replace(' ', ''), \
                f"pytest.ini contains exclusion pattern: {pattern}"
    
    print("✓ pytest.ini doesn't exclude test directories")


if __name__ == '__main__':
    # Run this test standalone to verify all tests are included
    print("Verifying all test directories are included in main test suite...")
    test_all_test_directories_are_discovered()
    test_no_test_directories_excluded_in_pytest_config()
    print("\n✓✓✓ All verification passed! ✓✓✓")