import 'package:flutter/services.dart';

enum AppIconVariant {
  defaultIcon,
  christmas,
  diwali,
  holi,
  newYear2027,
  newYear2028,
  newYear2029,
  newYear2030,
  newYear2031,
  rakhi,
  ramNavami,
  spring,
  summers,
  winters,
}

extension AppIconVariantInfo on AppIconVariant {
  /// PascalCase name sent to Android activity alias
  String get aliasName {
    switch (this) {
      case AppIconVariant.defaultIcon:
        return 'Default';
      case AppIconVariant.christmas:
        return 'Christmas';
      case AppIconVariant.diwali:
        return 'Diwali';
      case AppIconVariant.holi:
        return 'Holi';
      case AppIconVariant.newYear2027:
        return 'NewYear2027';
      case AppIconVariant.newYear2028:
        return 'NewYear2028';
      case AppIconVariant.newYear2029:
        return 'NewYear2029';
      case AppIconVariant.newYear2030:
        return 'NewYear2030';
      case AppIconVariant.newYear2031:
        return 'NewYear2031';
      case AppIconVariant.rakhi:
        return 'Rakhi';
      case AppIconVariant.ramNavami:
        return 'RamNavami';
      case AppIconVariant.spring:
        return 'Spring';
      case AppIconVariant.summers:
        return 'Summers';
      case AppIconVariant.winters:
        return 'Winters';
    }
  }

  String get label {
    switch (this) {
      case AppIconVariant.defaultIcon:
        return 'Default';
      case AppIconVariant.christmas:
        return 'Christmas 🎄';
      case AppIconVariant.diwali:
        return 'Diwali 🪔';
      case AppIconVariant.holi:
        return 'Holi 🎨';
      case AppIconVariant.newYear2027:
        return 'New Year 2027 🎉';
      case AppIconVariant.newYear2028:
        return 'New Year 2028 🎉';
      case AppIconVariant.newYear2029:
        return 'New Year 2029 🎉';
      case AppIconVariant.newYear2030:
        return 'New Year 2030 🎉';
      case AppIconVariant.newYear2031:
        return 'New Year 2031 🎉';
      case AppIconVariant.rakhi:
        return 'Rakhi 🪢';
      case AppIconVariant.ramNavami:
        return 'Ram Navami 🙏';
      case AppIconVariant.spring:
        return 'Spring 🌸';
      case AppIconVariant.summers:
        return 'Summers ☀️';
      case AppIconVariant.winters:
        return 'Winters ❄️';
    }
  }

  String get assetPath {
    switch (this) {
      case AppIconVariant.defaultIcon:
        return 'assets/images/app_icon.png';
      case AppIconVariant.christmas:
        return 'assets/images/app_icon_christmas.png';
      case AppIconVariant.diwali:
        return 'assets/images/app_icon_diwali.png';
      case AppIconVariant.holi:
        return 'assets/images/app_icon_holi.png';
      case AppIconVariant.newYear2027:
        return 'assets/images/app_icon_newyear2027.png';
      case AppIconVariant.newYear2028:
        return 'assets/images/app_icon_newyear2028.png';
      case AppIconVariant.newYear2029:
        return 'assets/images/app_icon_newyear2029.png';
      case AppIconVariant.newYear2030:
        return 'assets/images/app_icon_newyear2030.png';
      case AppIconVariant.newYear2031:
        return 'assets/images/app_icon_newyear2031.png';
      case AppIconVariant.rakhi:
        return 'assets/images/app_icon_rakhi.png';
      case AppIconVariant.ramNavami:
        return 'assets/images/app_icon_ramnavami.png';
      case AppIconVariant.spring:
        return 'assets/images/app_icon_spring.png';
      case AppIconVariant.summers:
        return 'assets/images/app_icon_summers.png';
      case AppIconVariant.winters:
        return 'assets/images/app_icon_winters.png';
    }
  }
}

class AppIconService {
  static const _channel = MethodChannel('com.campusmytra/app_icon');

  static Future<bool> changeIcon(AppIconVariant variant) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'changeIcon',
        {'iconName': variant.aliasName},
      );
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<AppIconVariant> getCurrentIcon() async {
    try {
      final name = await _channel.invokeMethod<String>('getCurrentIcon');
      return AppIconVariant.values.firstWhere(
        (v) => v.aliasName == name,
        orElse: () => AppIconVariant.defaultIcon,
      );
    } catch (e) {
      return AppIconVariant.defaultIcon;
    }
  }
}
