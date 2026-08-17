import 'dart:convert';

class UserModel {
  final String id;
  final String email;
  final String name;
  final String? photoUrl;
  final bool isEmailVerified;
  final String provider;
  final DateTime createdAt;
  final DateTime lastLoginAt;

  UserModel({
    required this.id,
    required this.email,
    required this.name,
    this.photoUrl,
    required this.isEmailVerified,
    required this.provider,
    required this.createdAt,
    required this.lastLoginAt,
  });

  // Convert to JSON
  String toJson() {
    return jsonEncode({
      'id': id,
      'email': email,
      'name': name,
      'photo_url': photoUrl,
      'is_email_verified': isEmailVerified,
      'provider': provider,
      'created_at': createdAt.toIso8601String(),
      'last_login_at': lastLoginAt.toIso8601String(),
    });
  }

  // Create from JSON
  static UserModel fromJson(String jsonString) {
    final Map<String, dynamic> json = jsonDecode(jsonString);
    return UserModel(
      id: json['id'],
      email: json['email'],
      name: json['name'],
      photoUrl: json['photo_url'],
      isEmailVerified: json['is_email_verified'] ?? false,
      provider: json['provider'] ?? 'email',
      createdAt: DateTime.parse(json['created_at']),
      lastLoginAt: DateTime.parse(json['last_login_at']),
    );
  }

  // Create from map
  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'],
      email: map['email'],
      name: map['name'],
      photoUrl: map['photo_url'],
      isEmailVerified: map['is_email_verified'] ?? false,
      provider: map['provider'] ?? 'email',
      createdAt: DateTime.parse(map['created_at']),
      lastLoginAt: DateTime.parse(map['last_login_at']),
    );
  }

  // Convert to map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'photo_url': photoUrl,
      'is_email_verified': isEmailVerified,
      'provider': provider,
      'created_at': createdAt.toIso8601String(),
      'last_login_at': lastLoginAt.toIso8601String(),
    };
  }

  // Copy with new values
  UserModel copyWith({
    String? id,
    String? email,
    String? name,
    String? photoUrl,
    bool? isEmailVerified,
    String? provider,
    DateTime? createdAt,
    DateTime? lastLoginAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      photoUrl: photoUrl ?? this.photoUrl,
      isEmailVerified: isEmailVerified ?? this.isEmailVerified,
      provider: provider ?? this.provider,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    );
  }

  @override
  String toString() {
    return 'UserModel(id: $id, email: $email, name: $name, provider: $provider)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

