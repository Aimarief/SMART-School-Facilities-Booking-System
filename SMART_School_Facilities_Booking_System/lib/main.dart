import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'web/manager_web_homepage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mobile/android_login.dart';
import 'web/web_login.dart';
import 'package:smart_school_facilities_booking_system/web/admin_web_homepage.dart';
import 'mobile/android_list_of_facilities.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'web/web_account.dart';
import 'dart:async';
import 'web/web_facilities.dart';
import 'web/web_list_manager.dart';

class UserRoleCache {
  static String? role;
}


class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) {
      notifyListeners();
    });
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

void main() async {

  WidgetsFlutterBinding.ensureInitialized();

  if(kIsWeb){
    await Firebase.initializeApp(options: FirebaseOptions(apiKey: "AIzaSyCnUEXvzFEMjcAuMCC46cQKmDdYrtIzoT0",
        authDomain: "schoolfacilitiesbookingsystem.firebaseapp.com",
        projectId: "schoolfacilitiesbookingsystem",
        storageBucket: "schoolfacilitiesbookingsystem.firebasestorage.app",
        messagingSenderId: "999888332644",
        appId: "1:999888332644:web:aadbf00cf2cc5b5a78bc71"));

    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
  }else{
    await Firebase.initializeApp();
  }





    runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();

    _router = GoRouter(
      refreshListenable: GoRouterRefreshStream(FirebaseAuth.instance.authStateChanges()),
      redirect: (BuildContext context, GoRouterState state) {
        final user = FirebaseAuth.instance.currentUser;
        final isLoggingIn = state.uri.path == '/login';

        if (user == null) {
          return isLoggingIn ? null : '/login';
        } else {
          if (isLoggingIn) {
            final role = UserRoleCache.role ?? '';
            if (role == 'Admin') return '/admin';
            if (role == 'Manager') return '/manager';
            return '/login';
          }
          return null;
        }
      },
      routes: [
        GoRoute(
          path: '/login',
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: WebLoginPage(),
          ),
        ),
        GoRoute(
          path: '/admin',
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: AdminWebHomepage(),
          ),
        ),
        GoRoute(
          path: '/manager',
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: ManagerWebHomepage(),
          ),
        ),
        GoRoute(
          path: '/webaccount',
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: WebAccount(),
          ),
        ),
        GoRoute(
          path: '/facilitiespage',
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: FacilitiesPage(),
          ),
        ),
        GoRoute(
          path: '/listmanagerpage',
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: WebListManager(),
          ),
        ),
      ],
    );

    // Add listener for route changes - CORRECTED VERSION
    _router.routerDelegate.addListener(() {
      final routeState = _router.routerDelegate.currentConfiguration;
      final location = routeState.uri.path;  // Get current path
      final user = FirebaseAuth.instance.currentUser;

      if (user != null && location == '/login') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _router.go(UserRoleCache.role == 'Admin' ? '/admin' : '/manager');
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _router.routerDelegate.removeListener(() {});
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: kIsWeb ? Size(1920, 1080) : Size(412, 915),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        if (kIsWeb) {
          // Web uses GoRouter
          return MaterialApp.router(
            debugShowCheckedModeBanner: false,
            title: 'SMART School Facility Booking System',
            theme: ThemeData(
              fontFamily: 'Poppins',
              textTheme: TextTheme(
                bodyLarge: TextStyle(fontSize: 20.sp),
                bodyMedium: TextStyle(fontSize: 15.sp),
                titleLarge: TextStyle(fontSize: 23.sp, fontWeight: FontWeight.bold),
              ),
            ),
            routerConfig: _router,
          );
        } else {
          // Mobile uses normal MaterialApp
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'SMART School Facility Booking System',
            theme: ThemeData(
              scaffoldBackgroundColor: Colors.white,
              fontFamily: 'Poppins',
              textTheme: TextTheme(
                bodyLarge: TextStyle(fontSize: 20.sp),
                bodyMedium: TextStyle(fontSize: 15.sp),
                titleLarge: TextStyle(fontSize: 23.sp, fontWeight: FontWeight.bold),
              ),
            ),
            home: AndroidLoginPage(), // your mobile starting page
          );
        }
      },
    );
  }
}

