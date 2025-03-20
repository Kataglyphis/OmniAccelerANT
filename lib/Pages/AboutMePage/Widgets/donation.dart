import 'package:flutter/material.dart';
import 'package:jotrockenmitlockenrepo/Decoration/row_divider.dart';
import 'package:jotrockenmitlockenrepo/Media/Image/openable_image.dart';

import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class Donation extends StatefulWidget {
  const Donation({
    super.key,
  });

  @override
  State<Donation> createState() => _DonationState();
}

class _DonationState extends State<Donation> {
  @override
  Widget build(BuildContext context) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Flexible(
                child: OpenableImage(
                  displayedImage: "assets/images/Pages/AboutMe/paypal.jpg",
                  disableOpen: true,
                ),
              ),
              Flexible(
                child: OpenableImage(
                  displayedImage:
                      "assets/images/Pages/AboutMe/Coffee-removebg.png",
                  disableOpen: false,
                ),
              ),
            ],
          ),
          rowDivider,
          Text(
            "${AppLocalizations.of(context)!.spendCoffe}\u2615",
            style: Theme.of(context).textTheme.titleLarge,
          )
        ]);
  }
}
