# Requirements Document

## Introduction

This feature enables real-time camera feed sharing between two mobile devices running the HackUMass Flutter application. One device acts as a camera source (sender) that streams its live camera feed, while another device acts as a receiver that displays the remote camera feed. This allows users to view and capture images from a remote camera as if it were their own device's camera, enabling collaborative image capture and AI-powered image description from remote locations.

The implementation includes both a Flutter mobile application and a lightweight signaling server that facilitates the initial connection handshake between devices. Once connected, video data flows directly between devices using peer-to-peer WebRTC connections.

## Glossary

- **Camera Source Device**: The mobile device that captures and streams its live camera feed to another device
- **Receiver Device**: The mobile device that receives and displays the live camera feed from a Camera Source Device
- **Camera Feed Stream**: The continuous transmission of video frames from the Camera Source Device to the Receiver Device
- **Connection Session**: An active peer-to-peer connection between a Camera Source Device and a Receiver Device
- **Feed Capture**: The action of taking a still image from the received Camera Feed Stream on the Receiver Device
- **HackUMass App**: The Flutter application that provides camera capture and AI image description functionality
- **Pairing Code**: A unique identifier used to establish a Connection Session between two devices
- **WebRTC**: Web Real-Time Communication protocol used for peer-to-peer video streaming
- **Signaling Server**: A server that facilitates the initial connection handshake between devices

## Requirements

### Requirement 1

**User Story:** As a user with a Camera Source Device, I want to start sharing my camera feed, so that another user can view my camera remotely

#### Acceptance Criteria

1. WHEN the user selects the "Share Camera" option, THE HackUMass App SHALL activate the device's camera and begin streaming the Camera Feed Stream
2. WHEN the Camera Feed Stream is active, THE HackUMass App SHALL generate and display a unique Pairing Code
3. WHILE the Camera Feed Stream is active, THE HackUMass App SHALL display a preview of the outgoing video feed
4. WHEN the user stops sharing, THE HackUMass App SHALL terminate the Camera Feed Stream and close the Connection Session
5. IF the Camera Feed Stream fails to initialize, THEN THE HackUMass App SHALL display an error message indicating camera access issues

### Requirement 2

**User Story:** As a user with a Receiver Device, I want to connect to a remote camera feed, so that I can view and capture images from another device's camera

#### Acceptance Criteria

1. WHEN the user selects the "Connect to Remote Camera" option, THE HackUMass App SHALL display an input field for entering a Pairing Code
2. WHEN the user enters a valid Pairing Code and confirms, THE HackUMass App SHALL establish a Connection Session with the corresponding Camera Source Device
3. WHEN the Connection Session is established, THE HackUMass App SHALL display the incoming Camera Feed Stream in real-time
4. IF the Pairing Code is invalid or the Camera Source Device is unavailable, THEN THE HackUMass App SHALL display an error message indicating connection failure
5. WHEN the user disconnects or the Camera Source Device stops sharing, THE HackUMass App SHALL terminate the Connection Session and return to the main screen

### Requirement 3

**User Story:** As a user with a Receiver Device, I want to capture still images from the remote camera feed, so that I can use the AI image description feature on remotely captured images

#### Acceptance Criteria

1. WHILE viewing a Camera Feed Stream, THE HackUMass App SHALL display a capture button
2. WHEN the user presses the capture button, THE HackUMass App SHALL extract the current video frame as a still image
3. WHEN a still image is captured from the Camera Feed Stream, THE HackUMass App SHALL save the image locally on the Receiver Device
4. WHEN a still image is captured, THE HackUMass App SHALL enable the "Describe Image" functionality for the captured image
5. THE HackUMass App SHALL maintain the Connection Session after capturing a still image to allow multiple captures

### Requirement 4

**User Story:** As a developer, I want a signaling server to facilitate device connections, so that two devices can discover each other and establish a peer-to-peer connection

#### Acceptance Criteria

1. THE Signaling Server SHALL accept WebSocket connections from HackUMass App instances
2. WHEN a Camera Source Device generates a Pairing Code, THE Signaling Server SHALL register the connection with that unique code
3. WHEN a Receiver Device submits a Pairing Code, THE Signaling Server SHALL relay WebRTC signaling messages between the two devices
4. WHEN WebRTC peer connection is established, THE Signaling Server SHALL allow the devices to communicate directly without routing video data
5. WHEN a Connection Session ends, THE Signaling Server SHALL remove the Pairing Code registration and clean up resources

### Requirement 5

**User Story:** As a user, I want the camera feed connection to be secure and private, so that my video stream cannot be intercepted by unauthorized parties

#### Acceptance Criteria

1. THE HackUMass App SHALL encrypt all Camera Feed Stream data using WebRTC encryption protocols
2. THE HackUMass App SHALL establish peer-to-peer connections that do not route video data through the Signaling Server
3. WHEN a Pairing Code is generated, THE HackUMass App SHALL ensure the code is unique and valid for a single Connection Session
4. WHEN a Connection Session is terminated, THE HackUMass App SHALL invalidate the associated Pairing Code
5. THE HackUMass App SHALL require explicit user action to start sharing a Camera Feed Stream

### Requirement 6

**User Story:** As a user, I want clear visual feedback about the connection status, so that I know when the camera feed is active and connected

#### Acceptance Criteria

1. WHILE attempting to establish a Connection Session, THE HackUMass App SHALL display a loading indicator
2. WHEN a Connection Session is successfully established, THE HackUMass App SHALL display a "Connected" status indicator
3. WHEN a Connection Session is active, THE HackUMass App SHALL display the connection duration
4. IF the connection quality degrades, THE HackUMass App SHALL display a warning indicator
5. WHEN a Connection Session is terminated, THE HackUMass App SHALL display a notification indicating disconnection

### Requirement 7

**User Story:** As a user with a Camera Source Device, I want to control which camera (front/back) is being shared, so that I can choose the appropriate camera view

#### Acceptance Criteria

1. WHEN sharing a Camera Feed Stream, THE HackUMass App SHALL default to the rear-facing camera
2. WHILE sharing a Camera Feed Stream, THE HackUMass App SHALL display a camera switch button
3. WHEN the user presses the camera switch button, THE HackUMass App SHALL toggle between front-facing and rear-facing cameras
4. WHEN the camera is switched, THE HackUMass App SHALL maintain the Connection Session without interruption
5. THE HackUMass App SHALL update the Camera Feed Stream within 2 seconds of the camera switch action
