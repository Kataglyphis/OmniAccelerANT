import 'package:jotrockenmitlockenrepo/Decoration/centered_box_decoration.dart';
import 'package:jotrockenmitlockenrepo/Decoration/component_group_decoration.dart';
import 'package:flutter/material.dart';

class ErrorPageWidget extends StatefulWidget {
  const ErrorPageWidget({
    super.key,
  });

  @override
  State<ErrorPageWidget> createState() => _ErrorPageWidget();
}

class _ErrorPageWidget extends State<ErrorPageWidget> {
  @override
  Widget build(BuildContext context) {
    const colDivider = SizedBox(height: 10);
    return ComponentGroupDecoration(label: 'Error 404', children: <Widget>[
      colDivider,
      CenteredBoxDecoration(
        borderRadius: 0,
        borderWidth: 5,
        color: Theme.of(context).colorScheme.primary,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(0),
          child: Image.asset("assets/images/Pages/Error/error404.gif"),
        ),
      ),
      colDivider
    ]);
  }
}
