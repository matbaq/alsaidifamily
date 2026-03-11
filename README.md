# Alsaidi Family Tree (Flutter)

تطبيق شجرة عائلة يعمل على Android / iOS / Web باستخدام Firebase.

## متطلبات التشغيل

- Flutter SDK (مستحسن: آخر إصدار Stable)
- Dart SDK (يأتي مع Flutter)
- Xcode 15+ لتشغيل iOS
- Android Studio / Android SDK لتشغيل Android
- CocoaPods (على macOS) لتجهيز iOS Pods

## إعداد المشروع

```bash
flutter pub get
```

## تشغيل التطبيق

### Android
```bash
flutter run -d android
```

### iOS
```bash
cd ios
pod install
cd ..
flutter run -d ios
```

> ملاحظة: تم توحيد حد iOS الأدنى إلى **13.0** في المشروع وPods.

### Web
```bash
flutter run -d chrome
```

## Firebase

المشروع يعتمد على:
- `google-services.json` داخل `android/app/`
- `GoogleService-Info.plist` داخل `ios/Runner/`
- `lib/firebase_options.dart`

إذا أردت ربط مشروع Firebase جديد:
```bash
flutterfire configure
```

## أوامر فحص الجودة

```bash
flutter analyze
flutter test
```

## ملاحظات استقرار مهمة

- في iOS يجب تنفيذ `pod install` بعد أي تعديل يعتمد على plugins.
- عند مشاكل بناء iOS:
```bash
flutter clean
flutter pub get
cd ios && pod install && cd ..
```
- عند مشاكل كاش Gradle في Android:
```bash
flutter clean
flutter pub get
```

## البنية الأساسية

- `lib/screens/family_tree_page.dart`: الشاشة الرئيسية للشجرة.
- `lib/widgets/family_tree/`: عناصر الرسم والتموضع (tree layout, painter, node widget).
- `lib/data/`: طبقة قراءة/كتابة البيانات.
- `lib/services/`: خدمات الأمان/الخصوصية.
