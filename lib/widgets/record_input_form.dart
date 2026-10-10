import 'package:flutter/material.dart';
import '../models/health_category.dart';
import '../models/record_data.dart';
import '../theme/app_colors.dart';

/// 統一的記錄輸入表單
class RecordInputForm extends StatefulWidget {
  final HealthCategory category;
  final Map<String, dynamic>? existingData;
  final Function(Map<String, dynamic>) onSave;

  const RecordInputForm({
    super.key,
    required this.category,
    this.existingData,
    required this.onSave,
  });

  @override
  State<RecordInputForm> createState() => _RecordInputFormState();
}

class _RecordInputFormState extends State<RecordInputForm> {
  late TextEditingController _valueController;
  late TextEditingController _systolicController;
  late TextEditingController _diastolicController;

  double _sliderValue = 0;
  String _selectedDropdownValue = '';
  String? _selectedTiming;
  int _waterCups = 0;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
  }

  void _initializeControllers() {
    final cat = widget.category;
    final existing = widget.existingData;

    _valueController = TextEditingController();
    _systolicController = TextEditingController();
    _diastolicController = TextEditingController();

    if (existing != null) {
      final value = existing['value']?.toString() ?? '';

      switch (cat.inputType) {
        case InputType.dualNumber:
          final match = RegExp(r'(\d+)/(\d+)').firstMatch(value);
          if (match != null) {
            _systolicController.text = match.group(1) ?? '';
            _diastolicController.text = match.group(2) ?? '';
          }
          break;

        case InputType.slider:
          final match = RegExp(r'(\d+\.?\d*)').firstMatch(value);
          if (match != null) {
            _sliderValue = double.tryParse(match.group(1) ?? '') ??
                double.tryParse(cat.defaultValue) ?? 0;
          }
          break;

        case InputType.dropdown:
          final match = RegExp(r'(.+?)\s+(\d+)').firstMatch(value);
          if (match != null) {
            _selectedDropdownValue = match.group(1) ?? cat.dropdownOptions?.first ?? '';
            _sliderValue = double.tryParse(match.group(2) ?? '') ??
                double.tryParse(cat.defaultValue) ?? 0;
          }
          break;

        case InputType.water:
          final numMatch = RegExp(r'(\d+)').firstMatch(value);
          if (numMatch != null) {
            final ml = int.tryParse(numMatch.group(1) ?? '') ?? 0;
            _waterCups = (ml / 250).round();
          }
          break;

        case InputType.singleNumber:
          final numValue = value.replaceAll(RegExp(r'[^0-9.]'), '').trim();
          _valueController.text = numValue;
          break;
      }

      _selectedTiming = existing['glucose_timing'] as String?;
    } else {
      // 設定預設值
      _sliderValue = double.tryParse(cat.defaultValue) ?? 0;
      _selectedDropdownValue = cat.dropdownOptions?.first ?? '';
      _waterCups = 1;
    }
  }

  @override
  void dispose() {
    _valueController.dispose();
    _systolicController.dispose();
    _diastolicController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildInputWidget(),
        if (widget.category.hasTimingOptions) ...[
          const SizedBox(height: 16),
          _buildTimingSelector(),
        ],
        if (widget.category.normalRangeHint != null) ...[
          const SizedBox(height: 12),
          _buildHintBox(),
        ],
      ],
    );
  }

  Widget _buildInputWidget() {
    switch (widget.category.inputType) {
      case InputType.singleNumber:
        return _buildSingleNumberInput();
      case InputType.dualNumber:
        return _buildDualNumberInput();
      case InputType.slider:
        return _buildSliderInput();
      case InputType.dropdown:
        return _buildDropdownWithSlider();
      case InputType.water:
        return _buildWaterInput();
    }
  }

  Widget _buildSingleNumberInput() {
    return TextField(
      controller: _valueController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: widget.category.name,
        hintText: widget.category.hintText ?? widget.category.defaultValue,
        suffixText: widget.category.unit,
        prefixIcon: Icon(
          widget.category.icon,
          color: widget.category.color,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: widget.category.color, width: 2),
        ),
      ),
    );
  }

  Widget _buildDualNumberInput() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _systolicController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '收縮壓',
              hintText: '120',
              suffixText: 'mmHg',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '/',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: TextField(
            controller: _diastolicController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '舒張壓',
              hintText: '80',
              suffixText: 'mmHg',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSliderInput() {
    final cat = widget.category;
    final min = cat.minValue ?? 0;
    final max = cat.maxValue ?? 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              cat.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: cat.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                cat.id == 'sleep'
                    ? '${_sliderValue.toStringAsFixed(1)} ${cat.unit}'
                    : '${_sliderValue.toInt()} ${cat.unit}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: cat.color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Slider(
          value: _sliderValue.clamp(min, max),
          min: min,
          max: max,
          divisions: cat.divisions ?? ((max - min) ~/ 1),
          activeColor: cat.color,
          inactiveColor: Colors.grey.shade300,
          onChanged: (value) {
            setState(() => _sliderValue = value);
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${min.toInt()} ${cat.unit}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            Text(
              '${max.toInt()} ${cat.unit}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDropdownWithSlider() {
    final cat = widget.category;
    final options = cat.dropdownOptions ?? [];
    final min = cat.minValue ?? 0;
    final max = cat.maxValue ?? 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 下拉選單
        DropdownButtonFormField<String>(
          initialValue: options.contains(_selectedDropdownValue)
              ? _selectedDropdownValue
              : options.first,
          decoration: InputDecoration(
            labelText: '${cat.name}類型',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          items: options.map((option) {
            return DropdownMenuItem(
              value: option,
              child: Row(
                children: [
                  Icon(_getExerciseIcon(option), size: 20, color: cat.color),
                  const SizedBox(width: 8),
                  Text(option),
                ],
              ),
            );
          }).toList(),
          onChanged: (value) {
            setState(() => _selectedDropdownValue = value ?? options.first);
          },
        ),
        const SizedBox(height: 20),
        // 時長滑桿
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '運動時長',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: cat.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_sliderValue.toInt()} ${cat.unit}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: cat.color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Slider(
          value: _sliderValue.clamp(min, max),
          min: min,
          max: max,
          divisions: cat.divisions ?? ((max - min) ~/ 5).toInt(),
          activeColor: cat.color,
          inactiveColor: Colors.grey.shade300,
          onChanged: (value) {
            setState(() => _sliderValue = value);
          },
        ),
      ],
    );
  }

  Widget _buildWaterInput() {
    final cat = widget.category;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              cat.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: cat.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_waterCups * 250} ml',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: cat.color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // 杯數選擇器
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: _waterCups > 0
                  ? () => setState(() => _waterCups--)
                  : null,
              icon: Icon(
                Icons.remove_circle_rounded,
                color: _waterCups > 0 ? cat.color : Colors.grey.shade300,
                size: 36,
              ),
            ),
            const SizedBox(width: 16),
            // 水杯視覺化
            ...List.generate(8, (index) {
              final isFilled = index < _waterCups;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Icon(
                  isFilled
                      ? Icons.local_drink_rounded
                      : Icons.local_drink_outlined,
                  color: isFilled ? cat.color : Colors.grey.shade300,
                  size: 28,
                ),
              );
            }),
            const SizedBox(width: 16),
            IconButton(
              onPressed: _waterCups < 16
                  ? () => setState(() => _waterCups++)
                  : null,
              icon: Icon(
                Icons.add_circle_rounded,
                color: _waterCups < 16 ? cat.color : Colors.grey.shade300,
                size: 36,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            '$_waterCups 杯 (每杯 250ml)',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimingSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '測量時機',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: RecordData.glucoseTimingOptions.map((option) {
            final isSelected = _selectedTiming == option['value'];
            return ChoiceChip(
              label: Text(option['label']!),
              selected: isSelected,
              selectedColor: widget.category.color.withValues(alpha: 0.3),
              backgroundColor: Colors.grey.shade100,
              labelStyle: TextStyle(
                color: isSelected ? widget.category.color : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              onSelected: (selected) {
                setState(() {
                  _selectedTiming = selected ? option['value'] : null;
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildHintBox() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.category.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: widget.category.color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.category.normalRangeHint!,
              style: TextStyle(
                fontSize: 13,
                color: widget.category.color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getExerciseIcon(String type) {
    switch (type) {
      case '跑步':
        return Icons.directions_run_rounded;
      case '走路':
        return Icons.directions_walk_rounded;
      case '騎車':
        return Icons.directions_bike_rounded;
      case '游泳':
        return Icons.pool_rounded;
      case '瑜珈':
        return Icons.self_improvement_rounded;
      case '重訓':
        return Icons.fitness_center_rounded;
      case '球類運動':
        return Icons.sports_soccer_rounded;
      default:
        return Icons.sports_rounded;
    }
  }

  /// 獲取表單數據
  Map<String, dynamic> getFormData() {
    final cat = widget.category;
    String value;
    String unit = cat.unit;

    switch (cat.inputType) {
      case InputType.dualNumber:
        value = '${_systolicController.text.trim()}/${_diastolicController.text.trim()} $unit';
        break;
      case InputType.slider:
        value = cat.id == 'sleep'
            ? '${_sliderValue.toStringAsFixed(1)} $unit'
            : '${_sliderValue.toInt()} $unit';
        break;
      case InputType.dropdown:
        value = '$_selectedDropdownValue ${_sliderValue.toInt()} $unit';
        break;
      case InputType.water:
        value = '${_waterCups * 250} $unit';
        break;
      case InputType.singleNumber:
        value = '${_valueController.text.trim()} $unit';
        break;
    }

    final data = <String, dynamic>{
      'category': cat.name,
      'value': value,
      'unit': unit,
    };

    if (cat.hasTimingOptions && _selectedTiming != null) {
      data['glucose_timing'] = _selectedTiming;
    }

    return data;
  }

  /// 驗證表單
  bool validate() {
    final cat = widget.category;

    switch (cat.inputType) {
      case InputType.dualNumber:
        return _systolicController.text.trim().isNotEmpty &&
            _diastolicController.text.trim().isNotEmpty;
      case InputType.singleNumber:
        return _valueController.text.trim().isNotEmpty;
      case InputType.slider:
      case InputType.dropdown:
      case InputType.water:
        return true; // 這些類型總是有效
    }
  }
}
