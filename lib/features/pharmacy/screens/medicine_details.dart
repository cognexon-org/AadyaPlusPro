import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_service.dart';

class MedicineDetails extends ConsumerStatefulWidget {
  final String medicineId;
  const MedicineDetails({super.key, required this.medicineId});

  @override
  ConsumerState<MedicineDetails> createState() => _MedicineDetailsState();
}

class _MedicineDetailsState extends ConsumerState<MedicineDetails> {
  bool _isLoading = true;
  Map<String, dynamic>? _medicine;
  List<dynamic> _batches = [];
  List<dynamic> _adjustments = [];

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService().getMedicineById(widget.medicineId);
      final data = response.data;
      setState(() {
        _medicine = data['medicine'];
        _batches = data['batches'] ?? [];
        _adjustments = data['adjustments'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading medicine details: $e')));
         setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_medicine == null) return const Scaffold(body: Center(child: Text('Medicine not found')));

    final name = _medicine!['medicineName'] ?? 'Medicine';
    final qty = _medicine!['quantity'] ?? 0;
    
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        title: Text(name, style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Overview Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
              child: Column(
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Current Stock', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppTheme.textSecondary)),
                    Text('$qty Units', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.accent)),
                  ]),
                  const Divider(height: 32),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    _info('Category', _medicine!['category'] ?? 'General'),
                    _info('Price', '₹${_medicine!['sellingPrice'] ?? 0}'),
                    _info('Prescription', _medicine!['prescriptionRequired'] == true ? 'Required' : 'None'),
                  ]),
                ],
              ),
            ),
            
            const SizedBox(height: 30),
            Text('Batches', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            _batches.isEmpty 
              ? Text('No active batches found', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.textTertiary))
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _batches.length,
                  itemBuilder: (context, index) {
                    final b = _batches[index];
                    final expiry = b['expiryDate'] != null ? DateFormat('MMM yyyy').format(DateTime.parse(b['expiryDate'])) : 'N/A';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                             Text('Batch: ${b['batchNumber']}', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600)),
                             Text('Expires: $expiry', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
                          ]),
                          Text('${b['availableQuantity']} left', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                        ],
                      ),
                    );
                  },
                ),
                
            const SizedBox(height: 30),
            Text('Recent Activities', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            ..._adjustments.map((a) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(color: (a['adjustmentType'] == 'addition' ? AppTheme.success : AppTheme.error).withValues(alpha: 0.1), shape: BoxShape.circle),
                    child: Center(child: Icon(a['adjustmentType'] == 'addition' ? Icons.add : Icons.remove, size: 16, color: a['adjustmentType'] == 'addition' ? AppTheme.success : AppTheme.error)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a['reason'] ?? 'Adjustment', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600)),
                    Text(DateFormat('dd MMM hh:mm a').format(DateTime.parse(a['createdAt'])), style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textTertiary)),
                  ])),
                  Text('${a['adjustmentQuantity'] > 0 ? '+' : ''}${a['adjustmentQuantity']}', 
                    style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.bold, color: a['adjustmentQuantity'] > 0 ? AppTheme.success : AppTheme.error)),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _info(String l, String v) => Column(children: [
    Text(l, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textTertiary)),
    const SizedBox(height: 4),
    Text(v, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
  ]);
}
