import 'package:flutter/material.dart';
import 'package:kataglyphis_inference_engine/Widgets/Navigation/old/Navbar/mobile/drawer_item.dart';
import 'package:kataglyphis_inference_engine/Widgets/Navigation/old/Navbar/mobile/navigation_drawer_change_notifier.dart';
import 'package:provider/provider.dart';
import 'package:kataglyphis_inference_engine/l10n/app_localizations.dart';

class NavigationDrawerWidget extends StatefulWidget {
  const NavigationDrawerWidget({super.key});

  @override
  State<NavigationDrawerWidget> createState() => _NavigationDrawerWidgetState();
}

class _NavigationDrawerWidgetState extends State<NavigationDrawerWidget> {
  Widget buildHeader(bool isCollapsed) =>
      isCollapsed
          ? Image.asset("assets/images/barbell.png", width: 48)
          : Row(
            children: [
              const SizedBox(width: 24),
              Image.asset("assets/images/barbell.png", width: 48),
              const SizedBox(width: 24),
              const Text(
                'Pump IT',
                style: TextStyle(fontSize: 32, color: Colors.black),
              ),
            ],
          );

  Widget buildCollapseIcon(BuildContext context, bool isCollapsed) {
    const double size = 52;
    final icon = isCollapsed ? Icons.arrow_forward_ios : Icons.arrow_back_ios;
    final alignment = isCollapsed ? Alignment.center : Alignment.centerRight;
    final margin = isCollapsed ? null : const EdgeInsets.only(right: 16);
    final width = isCollapsed ? double.infinity : size;
    return Container(
      alignment: alignment,
      margin: margin,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          child: SizedBox(
            width: width,
            height: size,
            child: Icon(icon, color: Colors.black),
          ),
          onTap: () {
            final provider = Provider.of<NavigationDrawerChangeNotifier>(
              context,
              listen: false,
            );
            provider.toggleIsCollapsed();
          },
        ),
      ),
    );
  }

  void selectItem(BuildContext context, int index) {
    switch (index) {
      case 0:
        Navigator.of(context).pushNamed('/aboutMe');
        break;
      case 1:
        Navigator.of(context).pushNamed('/quotes');
        break;
    }
  }

  buildMenuItem({
    required bool isCollapsed,
    required String text,
    required IconData icon,
    required void Function() onClicked,
  }) {
    const color = Colors.black;
    final leading = Icon(icon, color: color);

    return Material(
      color: Colors.transparent,
      child:
          isCollapsed
              ? ListTile(title: leading, onTap: onClicked)
              : ListTile(
                leading: leading,
                title: Text(
                  text,
                  style: const TextStyle(color: color, fontSize: 16),
                ),
                onTap: onClicked,
              ),
    );
  }

  buildList({required BuildContext context, required bool isCollapsed}) {
    List<DrawerItem> items = [
      DrawerItem(
        title: AppLocalizations.of(context)!.homepage,
        icon: Icons.account_box_outlined,
      ),
      DrawerItem(
        title: AppLocalizations.of(context)!.aboutme,
        icon: Icons.speaker_outlined,
      ),
    ];
    return ListView.separated(
      shrinkWrap: true,
      primary: false,
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final item = items[index];

        return buildMenuItem(
          isCollapsed: isCollapsed,
          text: item.title,
          icon: item.icon,
          onClicked: () => selectItem(context, index),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<NavigationDrawerChangeNotifier>(context);
    final isCollapsed = provider.isCollapsed;
    final safeArea = EdgeInsets.only(
      top: MediaQuery.of(context).viewPadding.top,
    );
    return SizedBox(
      width: isCollapsed ? MediaQuery.of(context).size.width * 0.2 : null,
      child: Drawer(
        child: Container(
          color: const Color.fromARGB(255, 255, 255, 255),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 24).add(safeArea),
                child: buildHeader(isCollapsed),
              ),
              buildList(context: context, isCollapsed: isCollapsed),
              const Spacer(),
              buildCollapseIcon(context, isCollapsed),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
