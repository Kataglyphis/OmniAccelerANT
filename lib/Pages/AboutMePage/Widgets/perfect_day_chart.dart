import 'package:flutter/material.dart';
import 'package:jotrockenmitlockenrepo/Decoration/Charts/pie_chart.dart';
import 'package:jotrockenmitlockenrepo/Decoration/Charts/pie_chart_data_entry.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:jotrockenmitlockenrepo/constants.dart';

class PerfectDay extends StatefulWidget {
  const PerfectDay({super.key});

  @override
  PerfectDayState createState() => PerfectDayState();
}

class PerfectDayState extends State<PerfectDay> {
  static double getDayHourPercantage(double houresPerDay) {
    double n = (houresPerDay / 24) * 100;
    return double.parse(n.toStringAsFixed(2));
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, double> chartConfig = {
      AppLocalizations.of(context)!.sleep: getDayHourPercantage(8),
      AppLocalizations.of(context)!.studying: getDayHourPercantage(8),
      AppLocalizations.of(context)!.sports: getDayHourPercantage(2),
      AppLocalizations.of(context)!.meditation: getDayHourPercantage(1),
      AppLocalizations.of(context)!.guitar: getDayHourPercantage(1),
      AppLocalizations.of(context)!.familyFriends: getDayHourPercantage(4)
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
