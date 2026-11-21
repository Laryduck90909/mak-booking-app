import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mak_booking/core/localization/app_localizations.dart';
import 'package:mak_booking/core/theme/app_theme.dart';
import 'package:mak_booking/models/contract.dart';
import 'package:mak_booking/models/design_request.dart';
import 'package:mak_booking/providers/app_providers.dart';
import 'package:mak_booking/shared/widgets/common.dart';
import 'package:signature/signature.dart';

class ContractScreen extends ConsumerStatefulWidget {
  const ContractScreen({super.key, required this.requestId});
  final String requestId;
  @override
  ConsumerState<ContractScreen> createState() => _ContractScreenState();
}

class _ContractScreenState extends ConsumerState<ContractScreen> {
  final _signature = SignatureController(
    penStrokeWidth: 3,
    penColor: MakColors.teal,
    exportBackgroundColor: Colors.white,
  );
  bool _signing = false;
  bool _signedLocally = false;

  @override
  void dispose() {
    _signature.dispose();
    super.dispose();
  }

  Future<void> _sign(MakContract contract, DesignRequest request) async {
    if (_signature.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('signatureRequired'))));
      return;
    }
    setState(() => _signing = true);
    try {
      final bytes = await _signature.toPngBytes();
      if (bytes == null) throw StateError('Signature export failed');
      await ref
          .read(requestRepositoryProvider)
          .signContract(contract, request, bytes);
      setState(() => _signedLocally = true);
      ref.invalidate(contractProvider(request));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('contractSigned'))));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _signing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = ref.watch(requestProvider(widget.requestId));
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('signContract'))),
      body: SafeArea(
        child: request.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ErrorState(error: error),
          data: (requestData) {
            if (requestData == null) {
              return ErrorState(error: StateError('Request not found'));
            }
            final contract = ref.watch(contractProvider(requestData));
            return contract.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => ErrorState(
                  error: error,
                  onRetry: () => ref.invalidate(contractProvider(requestData))),
              data: (data) {
                if (data == null) {
                  return EmptyState(
                    icon: Icons.description_outlined,
                    title: context.tr('contract'),
                    description: context.tr('contractUnavailable'),
                  );
                }
                final signed = data.isSigned || _signedLocally;
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        DefaultTabController(
                          length: 2,
                          child: Column(
                            children: [
                              const TabBar(
                                labelColor: MakColors.peach,
                                indicatorColor: MakColors.peach,
                                tabs: [
                                  Tab(text: 'العربية', height: 52),
                                  Tab(text: 'English', height: 52)
                                ],
                              ),
                              SizedBox(
                                height: 430,
                                child: Card(
                                  child: TabBarView(
                                    children: [
                                      _ContractText(
                                          text: data.bodyAr, rtl: true),
                                      _ContractText(
                                          text: data.bodyEn, rtl: false),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (signed)
                          const Card(
                            child: Padding(
                              padding: EdgeInsets.all(28),
                              child: Column(
                                children: [
                                  Icon(Icons.verified_rounded,
                                      size: 64, color: MakColors.success),
                                  SizedBox(height: 12),
                                  Text('✓',
                                      style: TextStyle(
                                          fontSize: 24,
                                          color: MakColors.success)),
                                ],
                              ),
                            ),
                          )
                        else ...[
                          Text(context.tr('signHere'),
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Signature(
                              controller: _signature,
                              height: 220,
                              backgroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _signing ? null : _signature.clear,
                                icon: const Icon(Icons.delete_outline_rounded),
                                label: Text(context.tr('clearSignature')),
                              ),
                              FilledButton.icon(
                                onPressed: _signing
                                    ? null
                                    : () => _sign(data, requestData),
                                icon: _signing
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))
                                    : const Icon(Icons.draw_rounded),
                                label: Text(context.tr('confirmSignature')),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ContractText extends StatelessWidget {
  const _ContractText({required this.text, required this.rtl});
  final String text;
  final bool rtl;
  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Text(text, style: const TextStyle(height: 1.9, fontSize: 15)),
        ),
      );
}
