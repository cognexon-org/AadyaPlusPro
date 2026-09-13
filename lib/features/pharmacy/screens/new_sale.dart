import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_service.dart';
import '../../dashboard/providers/dashboard_provider.dart';

class NewSaleScreen extends ConsumerStatefulWidget {
  const NewSaleScreen({super.key});

  @override
  ConsumerState<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends ConsumerState<NewSaleScreen> {
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _searchController = TextEditingController();

  List<dynamic> _cart = [];
  bool _isLoading = false;

  void _addToCart(dynamic medicine) {
    setState(() {
      final existingIndex = _cart.indexWhere((m) => m['_id'] == medicine['_id']);
      if (existingIndex >= 0) {
        if (_cart[existingIndex]['qty'] < medicine['quantity']) {
          _cart[existingIndex]['qty'] += 1;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot add more than available stock', style: TextStyle(color: Colors.white)), backgroundColor: AppTheme.error));
        }
      } else {
        if (medicine['quantity'] > 0) {
          _cart.add({...medicine, 'qty': 1});
        }
      }
    });
  }

  void _updateCartQty(int index, int change) {
    setState(() {
      final medicine = _cart[index];
      final newQty = medicine['qty'] + change;
      if (newQty <= 0) {
        _cart.removeAt(index);
      } else if (newQty > medicine['quantity']) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not enough stock available', style: TextStyle(color: Colors.white)), backgroundColor: AppTheme.error));
      } else {
        _cart[index]['qty'] = newQty;
      }
    });
  }

  double _getCartTotal() {
    double total = 0;
    for (var item in _cart) {
      final price = (item['sellingPrice'] ?? item['price'] ?? 0) as num;
      total += price.toDouble() * item['qty'];
    }
    return total;
  }

  Future<void> _submitSale() async {
    if (_cart.isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cart is empty'), backgroundColor: AppTheme.warning));
       return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      final items = _cart.map((m) => {
        'medicineId': m['_id'],
        'medicineName': m['medicineName'] ?? m['name'],
        'quantity': m['qty'],
        'sellingPrice': m['sellingPrice'] ?? m['price'] ?? 0,
        'taxRate': 0
      }).toList();

      final payload = {
        'customerType': 'walk-in',
        'customerName': _customerNameController.text.trim().isEmpty ? 'Walk-in Customer' : _customerNameController.text.trim(),
        'customerPhone': _customerPhoneController.text.trim(),
        'items': items,
        'paymentMethod': 'cash',
        'notes': 'App POS'
      };

      await ApiService().createPharmacySale(payload);
      
      // Refresh
      ref.read(pharmacyDashboardProvider.notifier).loadSales();
      ref.read(pharmacyDashboardProvider.notifier).loadMedicines();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sale completed successfully!'), backgroundColor: AppTheme.success));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dashData = ref.watch(pharmacyDashboardProvider);
    final medicines = dashData.appointments; // which stores medicines

    final searchQuery = _searchController.text.toLowerCase();
    final filteredMedicines = medicines.where((m) {
      final name = (m['medicineName'] ?? m['name'] ?? '').toString().toLowerCase();
      return name.contains(searchQuery);
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        title: Text('Point of Sale', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Current Cart
            if (_cart.isNotEmpty)
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3))),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Current Sale Items', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                        Text('${_cart.length} item(s)', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...List.generate(_cart.length, (i) {
                      final cItem = _cart[i];
                      final name = cItem['medicineName'] ?? cItem['name'];
                      final price = cItem['sellingPrice'] ?? cItem['price'] ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(child: Text(name, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.textPrimary))),
                            Row(
                              children: [
                                IconButton(onPressed: () => _updateCartQty(i, -1), icon: const Icon(Iconsax.minus_cirlce, size: 20, color: AppTheme.error), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                                const SizedBox(width: 8),
                                Text('${cItem['qty']}', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                                const SizedBox(width: 8),
                                IconButton(onPressed: () => _updateCartQty(i, 1), icon: const Icon(Iconsax.add_circle, size: 20, color: AppTheme.success), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                                const SizedBox(width: 16),
                                SizedBox(width: 60, child: Text('₹${price * cItem['qty']}', textAlign: TextAlign.right, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.accent))),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(height: 24),
                    TextField(
                      controller: _customerNameController,
                      decoration: const InputDecoration(hintText: 'Customer Name (Optional)', isDense: true),
                      style: GoogleFonts.plusJakartaSans(fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    Row(
                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
                       children: [
                         Text('Total Due', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                         Text('₹${_getCartTotal()}', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.accent)),
                       ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submitSale,
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
                        child: _isLoading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text('Complete Sale', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),

            // Medicine List
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search medicines to add...',
                  prefixIcon: const Icon(Iconsax.search_normal, size: 18, color: AppTheme.textTertiary),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
                ),
              ),
            ),
            
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: filteredMedicines.length,
                itemBuilder: (context, index) {
                  final m = filteredMedicines[index];
                  final name = m['medicineName'] ?? m['name'] ?? 'Medicine';
                  final price = m['sellingPrice'] ?? m['price'] ?? 0;
                  final stock = m['quantity'] ?? 0;
                  final brand = m['genericName'] ?? m['brand'] ?? '';
                  
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                              if (brand.toString().isNotEmpty)
                                Text(brand, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
                              Text('$stock in stock • ₹$price', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: stock > 0 ? AppTheme.success : AppTheme.error)),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () => _addToCart(m),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: stock > 0 ? AppTheme.accent.withValues(alpha: 0.1) : Colors.grey.shade100,
                            foregroundColor: stock > 0 ? AppTheme.accent : Colors.grey,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0)
                          ),
                          child: Text('Add', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
