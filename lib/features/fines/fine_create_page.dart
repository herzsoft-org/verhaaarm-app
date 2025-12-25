import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import 'fine_form_page.dart';

class FineCreatePage extends StatelessWidget {
  final ApiClient api;

  const FineCreatePage({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    return FineFormPage(api: api, mode: FineFormMode.official);
  }
}
