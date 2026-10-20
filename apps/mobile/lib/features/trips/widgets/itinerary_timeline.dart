import 'package:flutter/material.dart';
import '../models/trip_model.dart';
import 'itinerary_timeline_item.dart';

class ItineraryTimeline extends StatelessWidget {
  final List<ItineraryActivity> activities;
  const ItineraryTimeline({super.key, required this.activities});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: activities.length,
      itemBuilder: (context, index) {
        return ItineraryTimelineItem(
          activity: activities[index],
          isLast: index == activities.length - 1,
        );
      },
    );
  }
}
