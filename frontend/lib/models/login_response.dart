// lib/models/login_response.dart
class LoginResponse {
  final String accessToken;
  final String tokenType;
  final int userId;
  final String email;
  final String fullName;
  final String role;
  final int expiresIn;
  
  LoginResponse({
    required this.accessToken,
    required this.tokenType,
    required this.userId,
    required this.email,
    required this.fullName,
    required this.role,
    required this.expiresIn,
  });
  
  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      accessToken: json['access_token'],
      tokenType: json['token_type'],
      userId: json['user_id'],
      email: json['email'],
      fullName: json['full_name'],
      role: json['role'],
      expiresIn: json['expires_in'],
    );
  }
}

// lib/models/user.dart
class User {
  final int id;
  final String email;
  final String fullName;
  final String role;
  final bool isActive;
  
  User({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.isActive,
  });
  
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      email: json['email'],
      fullName: json['full_name'],
      role: json['role'],
      isActive: json['is_active'],
    );
  }
}