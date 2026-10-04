import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:uuid/uuid.dart';

// --- MODELOS DE DATOS ---
@HiveType(typeId: 0)
class Transaction extends HiveObject {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final double amount;
  @HiveField(2)
  final String title;
  @HiveField(3)
  final String category;
  @HiveField(4)
  final bool isExpense;
  @HiveField(5)
  final DateTime date;
  @HiveField(6)
  final String? receiptSource;

  Transaction({
    required this.id,
    required this.amount,
    required this.title,
    required this.category,
    required this.isExpense,
    required this.date,
    this.receiptSource,
  });
}

@HiveType(typeId: 1)
class Budget extends HiveObject {
  @HiveField(0)
  final String category;
  @HiveField(1)
  final double limit;

  Budget({required this.category, required this.limit});
}

// --- ADAPTADORES MANUALES (Para evitar dependencias extra) ---
class TransactionAdapter extends TypeAdapter<Transaction> {
  @override
  final int typeId = 0;
  @override
  Transaction read(BinaryReader reader) {
    return Transaction(
      id: reader.readString(),
      amount: reader.readDouble(),
      title: reader.readString(),
      category: reader.readString(),
      isExpense: reader.readBool(),
      date: DateTime.parse(reader.readString()),
      receiptSource: reader.read() as String?,
    );
  }
  @override
  void write(BinaryWriter writer, Transaction obj) {
    writer.writeString(obj.id);
    writer.writeDouble(obj.amount);
    writer.writeString(obj.title);
    writer.writeString(obj.category);
    writer.writeBool(obj.isExpense);
    writer.writeString(obj.date.toIso8601String());
    writer.write(obj.receiptSource);
  }
}

class BudgetAdapter extends TypeAdapter<Budget> {
  @override
  final int typeId = 1;
  @override
  Budget read(BinaryReader reader) {
    return Budget(category: reader.readString(), limit: reader.readDouble());
  }
  @override
  void write(BinaryWriter writer, Budget obj) {
    writer.writeString(obj.category);
    writer.writeDouble(obj.limit);
  }
}

// --- MAIN ---
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(TransactionAdapter());
  Hive.registerAdapter(BudgetAdapter());
  
  await Hive.openBox<Transaction>('transactions');
  await Hive.openBox<Budget>('budgets');
  
  var settings = await Hive.openBox('settings');
  if (settings.get('useStandardRule') == null) {
    settings.put('useStandardRule', false);
  }

  runApp(const FinanceApp());
}

class FinanceApp extends StatelessWidget {
  const FinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Finanzas Minimalistas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: const Color(0xFFE53935), 
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE53935),
          secondary: Color(0xFFFF5252),
          surface: Color(0xFF1E1E1E),
        ),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF121212), elevation: 0),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: Color(0xFFE53935)),
        useMaterial3: true,
      ),
      home: const DashboardScreen(),
    );
  }
}

// --- DASHBOARD ---
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _transactionBox = Hive.box<Transaction>('transactions');
  final _settingsBox = Hive.box('settings');

  final Map<String, Color> _categoryColors = {
    'Hogar': const Color(0xFF9E9E9E),
    'Alimentación': const Color(0xFFBDBDBD),
    'Transporte': const Color(0xFF757575),
    'Ocio': const Color(0xFFE53935), 
    'Salud': const Color(0xFFEEEEEE),
    'Otros': const Color(0xFF424242),
  };
  
  final Map<String, IconData> _categoryIcons = {
    'Hogar': Icons.home_outlined,
    'Alimentación': Icons.shopping_cart_outlined,
    'Transporte': Icons.directions_car_outlined,
    'Ocio': Icons.movie_outlined,
    'Salud': Icons.medical_services_outlined,
    'Otros': Icons.category_outlined,
  };

  double get _totalIncome => _transactionBox.values.where((t) => !t.isExpense).fold(0.0, (s, i) => s + i.amount);
  double get _totalExpense => _transactionBox.values.where((t) => t.isExpense).fold(0.0, (s, i) => s + i.amount);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Contabilidad', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [IconButton(icon: const Icon(Icons.settings), onPressed: () => _showSettings(context))],
      ),
      body: ValueListenableBuilder(
        valueListenable: _transactionBox.listenable(),
        builder: (context, Box<Transaction> box, _) {
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      _buildBalanceCard(),
                      const SizedBox(height: 24),
                      if (box.values.where((t) => t.isExpense).isNotEmpty) _buildChartCard(box),
                      const SizedBox(height: 24),
                      _buildFeedbackSection(),
                      const SizedBox(height: 24),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Categorías', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 12),
                      _buildCategoryGrid(),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddTransactionModal(context),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          const Text('Balance Total', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          Text('${(_totalIncome - _totalExpense).toStringAsFixed(2)} €', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildIncomeExpenseInfo('Ingresos', _totalIncome, Colors.white),
              _buildIncomeExpenseInfo('Gastos', _totalExpense, Theme.of(context).primaryColor),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIncomeExpenseInfo(String label, double amount, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        Text('${amount.toStringAsFixed(2)} €', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }

  Widget _buildChartCard(Box<Transaction> box) {
    Map<String, double> categoryTotals = {};
    for (var t in box.values.where((t) => t.isExpense)) {
      categoryTotals[t.category] = (categoryTotals[t.category] ?? 0) + t.amount;
    }
    return Container(
      height: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2, centerSpaceRadius: 40,
                sections: categoryTotals.entries.map((e) {
                  return PieChartSectionData(
                    color: _categoryColors[e.key] ?? Colors.grey,
                    value: e.value, title: '', radius: 20,
                  );
                }).toList(),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: ListView(
              children: categoryTotals.entries.map((e) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: _categoryColors[e.key] ?? Colors.grey)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(e.key, overflow: TextOverflow.ellipsis)),
                      Text('${e.value.toStringAsFixed(0)} €', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                );
              }).toList(),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildCategoryGrid() {
    return GridView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.5),
      itemCount: _categoryColors.keys.length,
      itemBuilder: (context, index) {
        String category = _categoryColors.keys.elementAt(index);
        double catExpense = _transactionBox.values.where((t) => t.isExpense && t.category == category).fold(0.0, (s, i) => s + i.amount);
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: _categoryColors[category]!.withOpacity(0.3))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_categoryIcons[category], color: _categoryColors[category]),
              const Spacer(),
              Text(category, style: const TextStyle(fontWeight: FontWeight.w500)),
              Text('${catExpense.toStringAsFixed(2)} €', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFeedbackSection() {
    bool useStandard = _settingsBox.get('useStandardRule', defaultValue: false);
    String feedbackText = '';
    Color feedbackColor = Colors.grey;

    if (_totalIncome == 0) {
      feedbackText = 'Añade ingresos para recibir consejos de optimización.';
    } else if (useStandard) {
      double ocioExpense = _transactionBox.values.where((t) => t.isExpense && t.category == 'Ocio').fold(0.0, (s, i) => s + i.amount);
      if (ocioExpense > _totalIncome * 0.30) {
        feedbackText = '¡Cuidado! Gastos de ocio superan el 30% (Regla 50/30/20).';
        feedbackColor = Theme.of(context).primaryColor;
      } else {
        feedbackText = 'Gastos de ocio dentro del 30% recomendado. ¡Genial!';
        feedbackColor = Colors.green;
      }
    } else {
      var budgetBox = Hive.box<Budget>('budgets');
      var ocioBudget = budgetBox.values.where((b) => b.category == 'Ocio').firstOrNull;
      if (ocioBudget != null) {
        double ocioExpense = _transactionBox.values.where((t) => t.isExpense && t.category == 'Ocio').fold(0.0, (s, i) => s + i.amount);
        if (ocioExpense > ocioBudget.limit) {
          feedbackText = 'Has superado tu límite de ${ocioBudget.limit}€ para Ocio.';
          feedbackColor = Theme.of(context).primaryColor;
        } else if (ocioExpense > ocioBudget.limit * 0.8) {
          feedbackText = 'Estás cerca de alcanzar tu presupuesto de Ocio.';
          feedbackColor = Colors.orange;
        } else {
           feedbackText = 'Presupuesto de Ocio bajo control.';
           feedbackColor = Colors.green;
        }
      } else {
        feedbackText = 'Ve a ajustes para definir un presupuesto o usar la regla 50/30/20.';
      }
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16), border: Border(left: BorderSide(color: feedbackColor, width: 4))),
      child: Row(children: [Icon(Icons.lightbulb_outline, color: feedbackColor), const SizedBox(width: 12), Expanded(child: Text(feedbackText, style: const TextStyle(fontSize: 13)))]),
    );
  }

  void _showAddTransactionModal(BuildContext context) {
    bool isExpense = true;
    String selectedCategory = 'Ocio';
    final amountController = TextEditingController();
    final titleController = TextEditingController();
    final receiptController = TextEditingController();

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ChoiceChip(label: const Text('Gasto'), selected: isExpense, selectedColor: Theme.of(context).primaryColor.withOpacity(0.3), onSelected: (val) => setState(() => isExpense = true)),
                      const SizedBox(width: 16),
                      ChoiceChip(label: const Text('Ingreso'), selected: !isExpense, selectedColor: Colors.green.withOpacity(0.3), onSelected: (val) => setState(() => isExpense = false)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cantidad (€)', border: OutlineInputBorder())),
                  const SizedBox(height: 16),
                  TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Descripción', border: OutlineInputBorder())),
                  const SizedBox(height: 16),
                  if (isExpense) DropdownButtonFormField<String>(
                    value: selectedCategory, items: _categoryColors.keys.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (val) => setState(() => selectedCategory = val!), decoration: const InputDecoration(labelText: 'Categoría', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  if (isExpense) TextField(controller: receiptController, decoration: const InputDecoration(labelText: 'Procedencia (Ej: Mercadona)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.receipt_long))),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
                      onPressed: () {
                        if (amountController.text.isEmpty || titleController.text.isEmpty) return;
                        _transactionBox.add(Transaction(
                          id: const Uuid().v4(), amount: double.parse(amountController.text), title: titleController.text,
                          category: isExpense ? selectedCategory : 'Ingreso', isExpense: isExpense, date: DateTime.now(), receiptSource: isExpense ? receiptController.text : null,
                        ));
                        Navigator.pop(context);
                      },
                      child: const Text('Guardar'),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          }
        );
      },
    );
  }

  void _showSettings(BuildContext context) {
    final budgetBox = Hive.box<Budget>('budgets');
    final budgetController = TextEditingController();
    var currentOcio = budgetBox.values.where((b) => b.category == 'Ocio').firstOrNull;
    if (currentOcio != null) budgetController.text = currentOcio.limit.toString();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            bool useStandard = _settingsBox.get('useStandardRule', defaultValue: false);
            return AlertDialog(
              backgroundColor: Theme.of(context).colorScheme.surface,
              title: const Text('Ajustes de Optimización'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text('Usar Regla 50/30/20'), subtitle: const Text('Ocio limitado al 30%'), activeColor: Theme.of(context).primaryColor,
                    value: useStandard, onChanged: (val) { setState(() => useStandard = val); _settingsBox.put('useStandardRule', val); this.setState(() {}); },
                  ),
                  if (!useStandard) ...[
                    const Divider(), const Text('Límite Personalizado para Ocio (€)'), const SizedBox(height: 8),
                    TextField(controller: budgetController, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder()))
                  ]
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    if (!useStandard && budgetController.text.isNotEmpty) {
                      final keys = budgetBox.keys.where((k) => budgetBox.get(k)?.category == 'Ocio').toList();
                      for (var key in keys) budgetBox.delete(key);
                      budgetBox.add(Budget(category: 'Ocio', limit: double.parse(budgetController.text)));
                    }
                    this.setState(() {}); Navigator.pop(context);
                  },
                  child: const Text('Guardar', style: TextStyle(color: Colors.white)),
                )
              ],
            );
          }
        );
      }
    );
  }
}
