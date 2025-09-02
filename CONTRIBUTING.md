# Contributing to Media Bridge

We welcome contributions to the Media Bridge project! This document provides guidelines for contributing.

## Getting Started

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/your-feature-name`)
3. Make your changes
4. Test your changes thoroughly
5. Commit with clear messages
6. Push to your fork
7. Create a Pull Request

## Areas for Contribution

### Code Improvements
- Performance optimizations
- Bug fixes
- New capture device support
- Platform compatibility improvements

### Documentation
- Improving clarity of existing docs
- Adding examples and tutorials
- Translating documentation

### Testing
- Adding unit tests
- Integration testing
- Performance benchmarking
- Device compatibility testing

## Development Guidelines

### Code Style

- Use consistent indentation (4 spaces)
- Follow modern C++ best practices
- Include appropriate comments
- Keep functions focused and small

### Commit Messages

- Use clear, descriptive commit messages
- Start with a verb (Add, Fix, Update, etc.)
- Keep the first line under 50 characters
- Add detailed description if needed

### Testing

- Test new features thoroughly
- Ensure no regressions in existing functionality
- Test on both Windows and Linux if possible
- For USB builds, test on real hardware
- Verify USB hot-plug recovery works

### Documentation

- Update documentation for any API changes
- Add comments for complex logic
- Update README if adding new features
- Keep CHANGELOG.md updated
- Document any new build requirements

## Pull Request Process

1. Ensure your PR has a clear description
2. Reference any related issues
3. Make sure all tests pass
4. Be responsive to review feedback
5. Keep your branch up to date with main

## Code of Conduct

- Be respectful and inclusive
- Welcome newcomers and help them get started
- Focus on constructive criticism
- Assume good intentions

## Building and Testing

### Local Build
```bash
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Debug ..
make -j$(nproc)  # Linux
cmake --build . --config Debug  # Windows
```

### Running Tests
```bash
# Run the binary with test devices
./ndi-capture --verbose

# Test USB hot-plug recovery
# 1. Start Media Bridge
# 2. Disconnect USB device
# 3. Wait for recovery attempt
# 4. Reconnect device
# 5. Verify stream resumes
```

## Questions?

Feel free to open an issue for any questions about contributing.
