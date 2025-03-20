import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:jotrockenmitlockenrepo/constants.dart';

const double buttonPaddingHorizontal = 40;
const double buttonPaddingVertical = 20;

class NavBar extends StatelessWidget {
  const NavBar({
    super.key,
    required this.colorSelected,
  });
  final ColorSeed colorSelected;
  @override
  Widget build(BuildContext context) {
    return DesktopNavbar(colorSelected: colorSelected);
  }
}

class DesktopNavbar extends StatelessWidget {
  const DesktopNavbar({super.key, required this.colorSelected});
  final ColorSeed colorSelected;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
      if (constraints.maxWidth > largeWidthBreakpoint) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            const SizedBox(
              height: 10,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: createLogoAndName(),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: createButtonArray(context),
            ),
          ],
        );
      } else {
        var buttons = createButtonArray(context);
        final numberButtonsFirstRow = (buttons.length / 2).round();
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: createLogoAndName(),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: buttons.sublist(0, numberButtonsFirstRow - 1),
            ),
            const SizedBox(
              height: 20,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: buttons.sublist(numberButtonsFirstRow, buttons.length),
            ),
          ],
        );
      }
    });
  }

  List<Widget> createLogoAndName() {
    return [
      // const Text(
      //   //appName,
      //   style: TextStyle(
      //       fontWeight: FontWeight.bold, color: Colors.black, fontSize: 60),
      // ),
      const SizedBox(width: 16),
      Image.asset("assets/images/barbell.png", width: 64),
    ];
  }

  List<Widget> createButtonArray(BuildContext context) {
    const buttonTextStyle = TextStyle(
        fontWeight: FontWeight.bold, color: Colors.black, fontSize: 20);
    const buttonSpacing = SizedBox(width: 30);
    var buttonStyle = ElevatedButton.styleFrom(
      backgroundColor: colorSelected.color,
      padding: const EdgeInsets.symmetric(
          horizontal: buttonPaddingHorizontal, vertical: buttonPaddingVertical),
    );
    return <Widget>[
      ElevatedButton(
        style: buttonStyle,
        child: Text(
          AppLocalizations.of(context)!.homepage,
          style: buttonTextStyle,
        ),
        onPressed: () {
          Navigator.pushNamed(context, '/aboutMe');
        },
      ),
      buttonSpacing,
      ElevatedButton(
        style: buttonStyle,
        child: Text(
          AppLocalizations.of(context)!.aboutme,
          style: buttonTextStyle,
        ),
        onPressed: () {
          Navigator.pushNamed(context, '/quotes');
        },
      ),
    ];
  }
}
