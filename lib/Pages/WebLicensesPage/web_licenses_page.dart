import 'package:anthology/Layout/ResponsiveDesign/single_page.dart';
import 'package:anthology/Pages/Footer/footer.dart';
import 'package:anthology/app_attributes.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';
import 'package:omni_accelerant/web_license_inventory.dart';

/// The licences page of the web build: what `/app/` ships, from the inventory its build wrote.
class WebLicensesPage extends StatefulWidget {
  const WebLicensesPage({
    super.key,
    required this.footer,
    required this.appAttributes,
    this.bundle,
  });

  final Footer footer;
  final AppAttributes appAttributes;

  /// Where the inventory and its texts come from; [rootBundle] when null.
  final AssetBundle? bundle;

  @override
  State<WebLicensesPage> createState() => _WebLicensesPageState();
}

class _WebLicensesPageState extends State<WebLicensesPage> {
  late final AssetBundle _bundle = widget.bundle ?? rootBundle;
  late final WebLicenseTexts _texts = WebLicenseTexts(_bundle);
  late final Future<WebLicenseInventory> _inventory = loadWebLicenseInventory(
    _bundle,
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return SinglePage(
      footer: widget.footer,
      appAttributes: widget.appAttributes,
      showMediumSizeLayout: widget.appAttributes.showMediumSizeLayout,
      showLargeSizeLayout: widget.appAttributes.showLargeSizeLayout,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(l10n.webLicensesIntro, style: textTheme.bodyLarge),
        ),
        FutureBuilder<WebLicenseInventory>(
          future: _inventory,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final WebLicenseInventory? inventory = snapshot.data;
            if (snapshot.hasError || inventory == null) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.webLicensesMissing,
                  style: textTheme.bodyLarge,
                ),
              );
            }
            return _InventoryView(inventory: inventory, texts: _texts);
          },
        ),
      ],
    );
  }
}

/// The group headings with their components, in the generator's order.
class _InventoryView extends StatelessWidget {
  const _InventoryView({required this.inventory, required this.texts});

  final WebLicenseInventory inventory;
  final WebLicenseTexts texts;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            l10n.webLicensesSummary(
              inventory.fileCount,
              inventory.components.length,
            ),
            style: textTheme.titleMedium,
          ),
        ),
        for (final (group, components) in inventory.groups) ...<Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              '${_groupTitle(l10n, group)} (${components.length})',
              style: textTheme.titleLarge,
            ),
          ),
          for (final component in components)
            _ComponentTile(component: component, texts: texts),
        ],
      ],
    );
  }
}

/// The localized heading of an inventory group; an unknown group keeps its key.
String _groupTitle(AppLocalizations l10n, String group) => switch (group) {
  'app' => l10n.webLicensesGroupApp,
  'engine' => l10n.webLicensesGroupEngine,
  'dart' => l10n.webLicensesGroupDart,
  'wasm' => l10n.webLicensesGroupWasm,
  'cargo' => l10n.webLicensesGroupCargo,
  'ort' => l10n.webLicensesGroupOrt,
  'models' => l10n.webLicensesGroupModels,
  'fonts' => l10n.webLicensesGroupFonts,
  'javascript' => l10n.webLicensesGroupJavascript,
  _ => group,
};

class _ComponentTile extends StatelessWidget {
  const _ComponentTile({required this.component, required this.texts});

  final WebLicenseComponent component;
  final WebLicenseTexts texts;

  @override
  Widget build(BuildContext context) {
    final String? license = component.license;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ExpansionTile(
        key: ValueKey<String>(component.id),
        title: Text(component.title),
        subtitle: license == null || license.isEmpty ? null : Text(license),
        children: <Widget>[
          _ComponentDetails(component: component, texts: texts),
        ],
      ),
    );
  }
}

/// More texts than this fold into tiles of their own, so the engine's notices load one project at a time.
const int _inlineTexts = 3;

/// A component's source, files and texts; built on first expansion, so its texts load only then.
class _ComponentDetails extends StatelessWidget {
  const _ComponentDetails({required this.component, required this.texts});

  final WebLicenseComponent component;
  final WebLicenseTexts texts;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final String? source = component.source;
    final bool folded = component.texts.length > _inlineTexts;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (source != null && source.isNotEmpty)
            SelectableText(l10n.webLicensesSource(source)),
          if (component.includes.isNotEmpty)
            SelectableText(
              l10n.webLicensesIncludes(component.includes.join(', ')),
            ),
          const SizedBox(height: 8),
          Text(
            l10n.webLicensesFiles(component.files.length),
            style: textTheme.titleSmall,
          ),
          SelectableText(component.files.join('\n')),
          for (final text in component.texts)
            if (folded)
              ExpansionTile(
                title: Text(text.title),
                children: <Widget>[_LicenseText(text: text, texts: texts)],
              )
            else ...<Widget>[
              const SizedBox(height: 12),
              Text(text.title, style: textTheme.titleSmall),
              _LicenseText(text: text, texts: texts),
            ],
        ],
      ),
    );
  }
}

/// One license text, loaded when it is first built.
class _LicenseText extends StatefulWidget {
  const _LicenseText({required this.text, required this.texts});

  final WebLicenseText text;
  final WebLicenseTexts texts;

  @override
  State<_LicenseText> createState() => _LicenseTextState();
}

class _LicenseTextState extends State<_LicenseText> {
  late final Future<String> _text = widget.texts.load(widget.text);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _text,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(AppLocalizations.of(context)!.webLicensesTextFailed);
        }
        final String? text = snapshot.data;
        if (text == null) {
          return const Padding(
            padding: EdgeInsets.all(8),
            child: LinearProgressIndicator(),
          );
        }
        return SelectableText(text);
      },
    );
  }
}
