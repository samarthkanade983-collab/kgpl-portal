class UserModel {
  final int id;
  final String name;
  final String email;
  final String role; // 'hr_admin' | 'team_leader' | 'intern'
  final bool isActive;
  final String? profilePhoto;
  final String? address;
  final String? contactNumber;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.isActive,
    this.profilePhoto,
    this.address,
    this.contactNumber,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] is int ? json['id'] : int.parse(json['id'].toString()),
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? 'intern',
      isActive: json['is_active'] == 1 || json['is_active'] == true,
      profilePhoto: json['profile_photo_path'],
      address: json['address'],
      contactNumber: json['contact_number'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'role': role,
    'is_active': isActive,
    'profile_photo_path': profilePhoto,
    'address': address,
    'contact_number': contactNumber,
  };
}
