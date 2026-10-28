import 'package:flutter/material.dart';

import 'ask_jamii_screen.dart';
import 'search_screen.dart';

Widget buildSearch(BuildContext context, {required VoidCallback onCashOut}) {
  return SearchScreen(
    onBack: () => Navigator.of(context).pop(),
    onAskJamii: () => Navigator.of(context).push(MaterialPageRoute(
      builder: (context) =>
          AskJamiiScreen(onBack: () => Navigator.of(context).pop()),
    )),
    onCashOut: onCashOut,
  );
}
