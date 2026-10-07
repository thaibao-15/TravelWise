import 'package:flutter/material.dart';
import 'trip_detail_screen.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/spacing.dart';

class TripsScreen extends StatelessWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('My Trips'), backgroundColor: Colors.white),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const TripDetailScreen()),
            );
          },
          child: const Text('View Da Nang Trip'),
        ),
      ),
    );
  }
}
