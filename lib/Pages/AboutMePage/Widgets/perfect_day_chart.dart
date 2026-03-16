import 'package:flutter/material.dart';
import 'package:jotrockenmitlockenrepo/Decoration/Charts/pie_chart.dart';
import 'package:jotrockenmitlockenrepo/Decoration/Charts/pie_chart_data_entry.dart';
import 'package:kataglyphis_inference_engine/l10n/app_localizations.dart';
import 'package:jotrockenmitlockenrepo/constants.dart';

class PerfectDay extends StatefulWidget {
  const PerfectDay({super.key});

  @override
  PerfectDayState createState() => PerfectDayState();
}

class PerfectDayState extends State<PerfectDay> {
  /// Calculates the percentage of a day that the given hours represent.
  ///
  /// Returns a value rounded to 2 decimal places.
  /// Example: 8 hours = 33.33% of a day.
  static double getDayHourPercentage(double hoursPerDay) {
    final percentage = (hoursPerDay / 24) * 100;
    return double.parse(percentage.toStringAsFixed(2));
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final Map<String, double> chartConfig = {
      localizations.sleep: getDayHourPercentage(8),
      localizations.studying: getDayHourPercentage(8),
      localizations.sports: getDayHourPercentage(2),
      localizations.meditation: getDayHourPercentage(1),
      localizations.guitar: getDayHourPercentage(1),
      localizations.familyFriends: getDayHourPercentage(4),
    };

    final List<PieChartDataEntry> chartData = [];
    chartConfig.forEach((entryName, valueInPercentage) {
      chartData.add(PieChartDataEntry(entryName, valueInPercentage));
    });
    double currentWidth = MediaQuery.of(context).size.width;
    return PieChartWidget(
      chartConfig: chartConfig,
      title: AppLocalizations.of(context)!.myPerfectDay,
      animate: currentWidth > narrowScreenWidthThreshold,
    );
  }
}
