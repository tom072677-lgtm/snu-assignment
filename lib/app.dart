import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/analytics.dart';
import 'core/theme.dart';
import 'features/assignments/presentation/assignments_screen.dart';
import 'features/calendar/presentation/calendar_screen.dart';
import 'features/map/presentation/map_screen.dart';
import 'features/restaurant/presentation/restaurant_screen.dart';
import 'features/timetable/presentation/timetable_screen.dart';
import 'shared/providers/settings_provider.dart';

class SharapApp extends ConsumerWidget {
  const SharapApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: '샤랍',
      theme: lightTheme(),
      darkTheme: darkTheme(),
      themeMode: themeMode,
      navigatorObservers: [Analytics.observer],
      home: const _MainShell(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class _MainShell extends ConsumerStatefulWidget {
  const _MainShell();

  @override
  ConsumerState<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<_MainShell> {
  int _index = 0;

  static const _screens = [
    AssignmentsScreen(),
    TimetableScreen(),
    CalendarScreen(),
    RestaurantScreen(),
    MapScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() => _index = i);
          Analytics.tabSelected(i);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: '과제',
          ),
          NavigationDestination(
            icon: Icon(Icons.table_chart_outlined),
            selectedIcon: Icon(Icons.table_chart),
            label: '시간표',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: '달력',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_outlined),
            selectedIcon: Icon(Icons.restaurant),
            label: '식당',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: '지도',
          ),
        ],
      ),
    );
  }
}
