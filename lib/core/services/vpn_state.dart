/// VPN connection states for multi-protocol service
enum VpnState {
  /// VPN is disconnected
  disconnected,
  
  /// VPN is attempting to connect
  connecting,
  
  /// VPN is connected and active
  connected,
  
  /// VPN is disconnecting
  disconnecting,
  
  /// VPN connection failed
  error,
  
  /// VPN is reconnecting
  reconnecting,
  
  /// VPN is preparing (checking permissions, etc.)
  preparing,
  
  /// VPN authentication is in progress
  authenticating,
  
  /// VPN permission denied
  denied,
  
  /// VPN waiting for connection
  waitConnection,
}

extension VpnStateExtension on VpnState {
  /// Get a human-readable name for the state
  String get name {
    switch (this) {
      case VpnState.disconnected:
        return 'Disconnected';
      case VpnState.connecting:
        return 'Connecting';
      case VpnState.connected:
        return 'Connected';
      case VpnState.disconnecting:
        return 'Disconnecting';
      case VpnState.error:
        return 'Error';
      case VpnState.reconnecting:
        return 'Reconnecting';
      case VpnState.preparing:
        return 'Preparing';
      case VpnState.authenticating:
        return 'Authenticating';
      case VpnState.denied:
        return 'Permission Denied';
      case VpnState.waitConnection:
        return 'Waiting Connection';
    }
  }

  /// Check if the VPN is in an active state
  bool get isActive {
    return this == VpnState.connected;
  }

  /// Check if the VPN is transitioning
  bool get isTransitioning {
    return this == VpnState.connecting ||
           this == VpnState.disconnecting ||
           this == VpnState.reconnecting ||
           this == VpnState.preparing ||
           this == VpnState.authenticating;
  }

  /// Check if the VPN is in an error state
  bool get isError {
    return this == VpnState.error;
  }

  /// Check if the VPN is disconnected
  bool get isDisconnected {
    return this == VpnState.disconnected;
  }
}

