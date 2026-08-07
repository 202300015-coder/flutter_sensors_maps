import 'package:flutter/material.dart';

import 'accelerometer_screen.dart';
import 'route_optimizer_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    AccelerometerScreen(),
    RouteOptimizerScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.speed),
            label: 'Acelerómetro',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Rutas',
          ),
        ],
      ),
    );
  }
}
