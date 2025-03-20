import 'package:flutter/material.dart';
import 'package:kataglyphis_inference_engine/Pages/AboutMePage/Widgets/donation.dart';
import 'package:jotrockenmitlockenrepo/Decoration/row_divider.dart';
import 'package:jotrockenmitlockenrepo/Media/Image/openable_image.dart';
import 'package:jotrockenmitlockenrepo/Media/email_button.dart';
import 'package:jotrockenmitlockenrepo/SocialMedia/social_media_widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:jotrockenmitlockenrepo/Decoration/col_divider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:jotrockenmitlockenrepo/user_settings.dart';

class AboutMeTable extends StatefulWidget {
  const AboutMeTable({
    super.key,
    required this.userSettings,
  });

  final UserSettings userSettings;
  @override
  AboutMeTableState createState() => AboutMeTableState();
}

class AboutMeTableState extends State<AboutMeTable> {
  AboutMeTableState({
    Key? key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        OpenableImage(
          displayedImage: widget.userSettings.assetPathImgOfMe!,
          imageCaptioning: widget.userSettings.myName,
          captioningStyle: Theme.of(context).textTheme.headlineLarge,
          disableOpen: true,
        ),
        Text(
          AppLocalizations.of(context)!.shortDescriptionTextMyPersona,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        rowDivider,
        SocialMediaWidgets(
          socialMediaLinksConfig: widget.userSettings.socialMediaLinksConfig!,
        ),
        rowDivider,
        EMailButton(
          title: AppLocalizations.of(context)!.mailMe,
          eMail: widget.userSettings.businessEmail!,
          firstName: widget.userSettings.firstName!,
        ),
        rowDivider,
        Text(
          widget.userSettings.businessEmail!,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        rowDivider,
        SizedBox(
          width: MediaQuery.of(context).size.width * 0.95,
          child: Text(
            widget.userSettings.myQuotation!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        rowDivider,
        const Donation(),
        rowDivider,
        Text(
          "I love to cURL",
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        IconButton(
          iconSize: 40,
          icon: const FaIcon(FontAwesomeIcons.dumbbell),
          onPressed: () {},
        ),
        colDivider,
      ],
    );
  }
}
