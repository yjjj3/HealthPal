import '../theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DietSettingsScreen extends StatefulWidget {
  const DietSettingsScreen({super.key});

  @override
  State<DietSettingsScreen> createState() => _DietSettingsScreenState();
}

class _DietSettingsScreenState extends State<DietSettingsScreen> {
  final TextEditingController _calorieController = TextEditingController();
  final TextEditingController _proteinController = TextEditingController();
  final TextEditingController _carbsController = TextEditingController();
  final TextEditingController _fatController = TextEditingController();
  
  String _selectedCondition = '糖尿病';
  final List<String> _healthConditions = [
    '糖尿病',
    '高血壓',
    '高血脂',
    '心臟病',
    '腎臟病',
    '一般健康',
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _calorieController.text = prefs.getString('target_calories') ?? '1800';
      _proteinController.text = prefs.getString('target_protein') ?? '70';
      _carbsController.text = prefs.getString('target_carbs') ?? '250';
      _fatController.text = prefs.getString('target_fat') ?? '60';
      _selectedCondition = prefs.getString('health_condition') ?? '糖尿病';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('target_calories', _calorieController.text);
    await prefs.setString('target_protein', _proteinController.text);
    await prefs.setString('target_carbs', _carbsController.text);
    await prefs.setString('target_fat', _fatController.text);
    await prefs.setString('health_condition', _selectedCondition);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('設定已儲存'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('飲食目標設定'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveSettings,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '健康狀況',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCondition,
                      items: _healthConditions.map((condition) {
                        return DropdownMenuItem(
                          value: condition,
                          child: Text(condition),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedCondition = value!;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '每日營養目標',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildNutritionInput(
                      label: '目標熱量 (kcal)',
                      controller: _calorieController,
                      icon: Icons.local_fire_department,
                    ),
                    _buildNutritionInput(
                      label: '蛋白質 (g)',
                      controller: _proteinController,
                      icon: Icons.fitness_center,
                    ),
                    _buildNutritionInput(
                      label: '碳水化合物 (g)',
                      controller: _carbsController,
                      icon: Icons.grain,
                    ),
                    _buildNutritionInput(
                      label: '脂肪 (g)',
                      controller: _fatController,
                      icon: Icons.water_drop,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI 飲食建議',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('取得個人化飲食建議'),
                      onPressed: () {
                        // 這裡可以呼叫 OpenAI 取得飲食建議
                        _getPersonalizedAdvice();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNutritionInput({
    required String label,
    required TextEditingController controller,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        keyboardType: TextInputType.number,
      ),
    );
  }

  void _getPersonalizedAdvice() async {
    // 這裡可以實現呼叫 OpenAI 取得建議的邏輯
    // 使用 _selectedCondition 和營養目標作為參數
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('AI 建議'),
        content: const Text('此功能開發中，將根據您的健康狀況提供個人化飲食建議。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }
}