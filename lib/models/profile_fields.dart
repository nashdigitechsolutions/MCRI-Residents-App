class ProfileFields {
  String firstName;
  String middleName;
  String lastName;
  String gender;
  String phone;
  String dateOfBirth;
  bool isStudent;
  String yearOfStudy;
  String cohort;
  String emergencyContactName;
  String emergencyContactPhone;
  String bio;
  bool isAvailable;

  ProfileFields({
    this.firstName = '',
    this.middleName = '',
    this.lastName = '',
    this.gender = '',
    this.phone = '',
    this.dateOfBirth = '',
    this.isStudent = false,
    this.yearOfStudy = '',
    this.cohort = '',
    this.emergencyContactName = '',
    this.emergencyContactPhone = '',
    this.bio = '',
    this.isAvailable = true,
  });

  ProfileFields copy() {
    return ProfileFields(
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      gender: gender,
      phone: phone,
      dateOfBirth: dateOfBirth,
      isStudent: isStudent,
      yearOfStudy: yearOfStudy,
      cohort: cohort,
      emergencyContactName: emergencyContactName,
      emergencyContactPhone: emergencyContactPhone,
      bio: bio,
      isAvailable: isAvailable,
    );
  }

  factory ProfileFields.fromJson(Map<String, dynamic> json) {
    return ProfileFields(
      firstName: json['first_name'] as String? ?? '',
      middleName: json['middle_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      gender: json['gender'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      dateOfBirth: json['date_of_birth'] as String? ?? '',
      isStudent: json['is_student'] as bool? ?? false,
      yearOfStudy: json['year_of_study']?.toString() ?? '',
      cohort: json['cohort']?.toString() ?? '',
      emergencyContactName: json['emergency_contact_name'] as String? ?? '',
      emergencyContactPhone: json['emergency_contact_phone'] as String? ?? '',
      bio: json['bio'] as String? ?? '',
      isAvailable: json['is_available'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'is_student': isStudent,
      'is_available': isAvailable,
    };

    void addIfNotEmpty(String key, String value) {
      if (value.isNotEmpty) json[key] = value;
    }

    addIfNotEmpty('first_name', firstName);
    addIfNotEmpty('middle_name', middleName);
    addIfNotEmpty('last_name', lastName);
    addIfNotEmpty('gender', gender);
    addIfNotEmpty('phone', phone);
    addIfNotEmpty('date_of_birth', dateOfBirth);
    addIfNotEmpty('cohort', cohort);
    addIfNotEmpty('emergency_contact_name', emergencyContactName);
    addIfNotEmpty('emergency_contact_phone', emergencyContactPhone);
    addIfNotEmpty('bio', bio);

    if (yearOfStudy.isNotEmpty) {
      final y = int.tryParse(yearOfStudy);
      if (y != null) json['year_of_study'] = y;
    }

    return json;
  }
}

const genderOptions = [
  {'value': 'male', 'label': 'Male'},
  {'value': 'female', 'label': 'Female'},
  {'value': 'other', 'label': 'Other'},
];
