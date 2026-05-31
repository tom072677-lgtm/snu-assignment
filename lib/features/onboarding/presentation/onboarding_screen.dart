import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/snu_departments.dart';
import '../../../shared/providers/settings_provider.dart';

/// 최초 실행 시 단과대 → 학과 2단계 온보딩.
/// 완료 시 SharedPreferences에 college/department 코드 저장 후 팝.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0; // 0: 단과대 선택, 1: 학과 선택
  SnuCollege? _selectedCollege;

  void _selectCollege(SnuCollege college) {
    setState(() {
      _selectedCollege = college;
      _step = 1;
    });
  }

  void _selectDepartment(SnuDepartment dept) {
    ref.read(collegeCodeProvider.notifier).set(_selectedCollege!.code);
    ref.read(departmentCodeProvider.notifier).set(dept.code);
    ref.read(onboardingCompleteProvider.notifier).set(true);
  }

  void _goBack() => setState(() => _step = 0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_step == 1)
                    GestureDetector(
                      onTap: _goBack,
                      child: Row(
                        children: [
                          const Icon(Icons.arrow_back_ios,
                              size: 16, color: Color(0xFF555555)),
                          Text(
                            _selectedCollege!.name,
                            style: const TextStyle(
                                fontSize: 14, color: Color(0xFF555555)),
                          ),
                        ],
                      ),
                    ),
                  if (_step == 1) const SizedBox(height: 12),
                  const Text(
                    '샤랍',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A73E8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _step == 0
                        ? '소속 단과대학을 선택해주세요\n제휴 식당 및 복지 혜택을 확인할 수 있어요.'
                        : '학과/학부를 선택해주세요',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF444444),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            // 단계 표시
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  const _StepDot(active: true, label: '단과대'),
                  _StepLine(active: _step == 1),
                  _StepDot(active: _step == 1, label: '학과'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // 목록
            Expanded(
              child: _step == 0 ? _buildCollegeList() : _buildDeptList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollegeList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: snuColleges.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (_, i) {
        final college = snuColleges[i];
        return ListTile(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          tileColor: const Color(0xFFF5F7FF),
          title: Text(
            college.name,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${college.departments.length}개 학과',
            style: const TextStyle(fontSize: 13, color: Color(0xFF888888)),
          ),
          trailing: const Icon(Icons.chevron_right, color: Color(0xFFAAAAAA)),
          onTap: () => _selectCollege(college),
        );
      },
    );
  }

  Widget _buildDeptList() {
    final depts = _selectedCollege!.departments;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: depts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (_, i) {
        final dept = depts[i];
        return ListTile(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          tileColor: const Color(0xFFF5F7FF),
          title: Text(dept.name,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          trailing: const Icon(Icons.chevron_right, color: Color(0xFFAAAAAA)),
          onTap: () => _selectDepartment(dept),
        );
      },
    );
  }
}

class _StepDot extends StatelessWidget {
  final bool active;
  final String label;
  const _StepDot({required this.active, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? const Color(0xFF1A73E8) : const Color(0xFFDDDDDD),
          ),
          child: Center(
            child: Icon(
              active ? Icons.check : Icons.circle,
              size: active ? 14 : 8,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: active
                    ? const Color(0xFF1A73E8)
                    : const Color(0xFF999999))),
      ],
    );
  }
}

class _StepLine extends StatelessWidget {
  final bool active;
  const _StepLine({required this.active});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: active ? const Color(0xFF1A73E8) : const Color(0xFFDDDDDD),
      ),
    );
  }
}
