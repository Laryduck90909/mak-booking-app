import 'package:flutter/material.dart';
import 'package:mak_booking/core/localization/app_localizations.dart';
import 'package:mak_booking/core/theme/app_theme.dart';
import 'package:mak_booking/shared/widgets/brand_logo.dart';

class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.service});
  final String service;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(context.tr(service))),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  children: [
                    const BrandLogo(size: 72),
                    const SizedBox(height: 40),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                          color: MakColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(30)),
                      child: Text(context.tr('comingSoon'),
                          style: const TextStyle(
                              color: MakColors.peach,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 20),
                    Text(context.tr(service),
                        style: Theme.of(context)
                            .textTheme
                            .displaySmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    Text(context.tr('comingSoonDesc'),
                        style: const TextStyle(
                            color: MakColors.muted, height: 1.8),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 32),
                    FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(context.tr('back'))),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
