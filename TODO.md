# NDI Bridge Development TODO

## Format Guide
Each task follows this structure:
- [ ] Task description
  - **ID**: NDI-XXX
  - **Branch**: feature/branch-name
  - **Priority**: High/Medium/Low
  - **Status**: Planning/In Progress/Review/Complete
  - **Details**: Additional notes

## Active Tasks

### High Priority

- [ ] Fix blinking welcome loop dashboard
  - **ID**: NDI-001
  - **Branch**: feature/fix-welcome-dashboard
  - **Priority**: High
  - **Status**: Planning
  - **Details**: Solve the blinking issue in the TTY2 welcome loop dashboard display

- [ ] Verify and modernize test suite
  - **ID**: NDI-002
  - **Branch**: feature/modernize-tests
  - **Priority**: High
  - **Status**: Planning
  - **Details**: Ensure all tests follow one modern design approach, verify they focus on real functionality, and achieve 100% success rate

### Medium Priority

- [ ] Fix dynamic MAC address on bridge interface
  - **ID**: NDI-003
  - **Branch**: feature/static-mac-bridge
  - **Priority**: Medium
  - **Status**: Planning
  - **Details**: Solve issue where bridge interface gets different MAC addresses after each image build, causing DHCP to assign different IPs on the same PC. Need to implement static/persistent MAC address for br0 interface.

- [ ] Simple web intercom control interface
  - **ID**: NDI-004
  - **Branch**: feature/web-intercom
  - **Priority**: Medium
  - **Status**: Planning
  - **Details**: Add web-based intercom control with mute button and volume slider for easy audio management

- [ ] Dante audio bridge integration
  - **ID**: NDI-005
  - **Branch**: feature/dante-bridge
  - **Priority**: Medium
  - **Status**: Planning
  - **Details**: Add Audinate Dante bridge support for routing audio from soundcard to/from Dante network using Inferno (software Dante implementation)

### Low Priority

- [ ] Add comprehensive monitoring dashboard
  - **ID**: NDI-006
  - **Branch**: feature/monitoring-dashboard
  - **Priority**: Low
  - **Status**: Planning
  - **Details**: Future enhancement for better system monitoring

## Completed Tasks

- [x] Add NDI audio output support
  - **ID**: NDI-000
  - **Branch**: feature/ndi-audio-output
  - **Priority**: High
  - **Status**: Complete
  - **Details**: Implemented ALSA-based audio output for NDI streams
  - **Completed**: 2025-08-23

## Notes

### Task Management
- Tasks are tracked with unique IDs for easy reference
- Each task should have its own feature branch
- Priority levels help focus development efforts
- Status tracking shows progress through the development lifecycle

### How to Use This File
1. When starting work on a task, update its status to "In Progress"
2. Create the specified branch for development
3. Update status to "Review" when ready for testing
4. Mark as "Complete" when merged to main

### Claude Integration
This format is optimized for Claude to:
- Parse and display tasks by priority or status
- Update task progress automatically
- Create branches for new features
- Track completion metrics