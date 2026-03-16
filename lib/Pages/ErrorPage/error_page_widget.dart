import 'package:flutter/material.dart';
import 'package:jotrockenmitlockenrepo/Decoration/centered_box_decoration.dart';
import 'package:jotrockenmitlockenrepo/Decoration/component_group_decoration.dart';

/// Widget displaying a 404 error page with an animated GIF.
///
/// This is a stateless widget since it has no mutable state.
class ErrorPageWidget extends StatelessWidget {
  const ErrorPageWidget({super.key});

  @override
  Widget build(BuildContext context) {
    const colDivider = SizedBox(height: 10);
    return ComponentGroupDecoration(
      label: 'Error 404',
      children: <Widget>[
        colDivider,
        CenteredBoxDecoration(
          borderRadius: 0,
          borderWidth: 5,
          color: Theme.of(context).colorScheme.primary,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(0),
            child: Image.asset('assets/images/Pages/Error/error404.gif'),
          ),
        ),
        colDivider,
      ],
    );
  }
}
