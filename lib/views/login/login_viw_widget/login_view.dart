import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:ycd/routes/app_routes.dart';

import 'login_controller.dart';

class LoginWidget extends GetView<LoginController> {
  const LoginWidget({super.key});

  static const Color _gold = Color(0xFFD4B896);
  static const Color _goldDark = Color(0xFFC9A86C);
  static const Color _textLight = Color(0xFFE8E4DC);
  static const Color _textMuted = Color(0x99FFFFFF);
  static const Color _inputFill = Color(0xFF332F2D);
  static const double _loginButtonAspectRatio = 1020 / 150;

  @override
  Widget build(BuildContext context) {
    final c = Get.find<LoginController>();
    final mediaQuery = MediaQuery.of(context);
    // SafeArea keeps the bottom system inset, so only the remaining portion of
    // the IME actually obscures its child.
    final keyboardOcclusion = mediaQuery.viewInsets.bottom > mediaQuery.viewPadding.bottom
        ? mediaQuery.viewInsets.bottom - mediaQuery.viewPadding.bottom
        : 0.0;

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildBackground(),
          SafeArea(
            maintainBottomViewPadding: true,
            child: CustomSingleChildLayout(
              key: const ValueKey('login-content-layout'),
              delegate: _LoginContentLayoutDelegate(
                keyboardOcclusion: keyboardOcclusion,
              ),
              child: SingleChildScrollView(
                key: const ValueKey('login-scroll-view'),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.symmetric(horizontal: 28.w),
                child: Obx(() {
                  final isLoginTab = c.state.authTabIndex.value == 0;
                  return Column(
                    key: const ValueKey('login-content'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildAuthTabs(c),
                      SizedBox(height: 28.h),
                      if (isLoginTab) ...[
                        Form(
                          key: c.formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildInput(
                                controller: c.userNameController,
                                hint: '请输入账号',
                                prefix: Icons.person_outline,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return '请输入账号';
                                  }
                                  return null;
                                },
                              ),
                              SizedBox(height: 12.h),
                              Obx(
                                () => _buildInput(
                                  controller: c.passwordController,
                                  hint: '请输入登录密码',
                                  prefix: Icons.lock_outline,
                                  obscureText: c.state.isPasswordVisible.value,
                                  suffix: IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: BoxConstraints(minWidth: 40.w, minHeight: 40.h),
                                    splashRadius: 18.r,
                                    onPressed: c.togglePasswordVisibility,
                                    icon: Icon(
                                      c.state.isPasswordVisible.value
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      color: _gold,
                                      size: 20.w,
                                    ),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return '请输入密码';
                                    }
                                    if (value.length < 2) {
                                      return '密码长度至少2位';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              SizedBox(height: 12.h),
                              _buildRememberRow(c),
                              SizedBox(height: 20.h),
                              Obx(() => _buildLoginButton(c)),
                            ],
                          ),
                        ),
                        SizedBox(height: 24.h),
                        _buildSkipEntry(),
                        SizedBox(height: 20.h),
                        _buildServiceEntry(c),
                      ] else
                        Form(
                          key: c.formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildInput(
                                controller: c.registerUsernameController,
                                hint: '请输入账号',
                                prefix: Icons.person_outline,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return '请输入账号';
                                  }
                                  return null;
                                },
                              ),
                              SizedBox(height: 12.h),
                              _buildInput(
                                controller: c.nicknameController,
                                hint: '昵称（选填，默认使用账号）',
                                prefix: Icons.badge_outlined,
                              ),
                              SizedBox(height: 12.h),
                              _buildInput(
                                controller: c.phoneController,
                                hint: '手机号（选填）',
                                prefix: Icons.phone_outlined,
                              ),
                              SizedBox(height: 12.h),
                              Obx(
                                () => _buildInput(
                                  controller: c.registerPasswordController,
                                  hint: '请输入密码',
                                  prefix: Icons.lock_outline,
                                  obscureText: c.state.isPasswordVisible.value,
                                  suffix: _buildPasswordVisibilityButton(c),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return '请输入密码';
                                    }
                                    if (value.length < 2) {
                                      return '密码长度至少2位';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              SizedBox(height: 12.h),
                              Obx(
                                () => _buildInput(
                                  controller: c.confirmPasswordController,
                                  hint: '请再次输入密码',
                                  prefix: Icons.lock_outline,
                                  obscureText: c.state.isPasswordVisible.value,
                                  suffix: _buildPasswordVisibilityButton(c),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return '请再次输入密码';
                                    }
                                    if (value != c.registerPasswordController.text) {
                                      return '两次输入的密码不一致';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              SizedBox(height: 20.h),
                              _buildRegisterButton(c),
                              SizedBox(height: 16.h),
                              Text(
                                '注册功能暂未开放,请联系管理员',
                                style: TextStyle(fontSize: 13.sp, color: _textMuted),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    return Image.asset(
      'assets/images/login_bg.png',
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      errorBuilder: (_, __, ___) => Image.asset(
        'assets/images/game_backgroud.jpg',
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
      ),
    );
  }

  Widget _buildAuthTabs(LoginController c) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildTabItem(c, index: 0, label: '登录'),
        SizedBox(width: 48.w),
        _buildTabItem(c, index: 1, label: '注册'),
      ],
    );
  }

  Widget _buildTabItem(LoginController c, {required int index, required String label}) {
    return Obx(() {
      final selected = c.state.authTabIndex.value == index;
      return GestureDetector(
        onTap: () => c.state.authTabIndex.value = index,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 18.sp,
                color: selected ? _textLight : _textMuted,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            SizedBox(height: 8.h),
            Container(
              width: 28.w,
              height: 3.h,
              decoration: BoxDecoration(
                color: selected ? _goldDark : Colors.transparent,
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildRememberRow(LoginController c) {
    return Obx(
      () => Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(4.r),
            onTap: () => c.state.autoLogin.value = !c.state.autoLogin.value,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 12.w),
                Container(
                  width: 16.w,
                  height: 16.w,
                  decoration: BoxDecoration(
                    color: c.state.autoLogin.value ? _gold : Colors.transparent,
                    borderRadius: BorderRadius.circular(4.r),
                    border: Border.all(color: _gold.withValues(alpha: 0.8), width: 1.w),
                  ),
                  child: c.state.autoLogin.value ? Icon(Icons.check, color: const Color(0xFF2A2218), size: 12.w) : null,
                ),
                SizedBox(width: 6.w),
                Text(
                  '记住密码',
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: _textLight.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: c.showContactAdminTip,
            child: Text(
              '忘记密码?',
              style: TextStyle(
                fontSize: 13.sp,
                color: _textLight.withValues(alpha: 0.85),
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginButton(LoginController c) {
    final loading = c.state.isLoading.value;
    return AspectRatio(
      aspectRatio: _loginButtonAspectRatio,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: loading ? null : c.login,
          borderRadius: BorderRadius.circular(999),
          child: Stack(
            alignment: Alignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: Image.asset(
                  'assets/images/login_button.png',
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.fill,
                ),
              ),
              if (loading)
                SizedBox(
                  width: 22.w,
                  height: 22.w,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3D3428)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRegisterButton(LoginController c) {
    return SizedBox(
      width: double.infinity,
      height: 50.h,
      child: ElevatedButton(
        onPressed: c.registerNotAvailable,
        style: ElevatedButton.styleFrom(
          backgroundColor: _gold,
          foregroundColor: const Color(0xFF2A2218),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999.r)),
        ),
        child: Text(
          '确认注册',
          style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildPasswordVisibilityButton(LoginController c) {
    return IconButton(
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: 40.w, minHeight: 40.h),
      splashRadius: 18.r,
      onPressed: c.togglePasswordVisibility,
      icon: Icon(
        c.state.isPasswordVisible.value ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        color: _gold,
        size: 20.w,
      ),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String hint,
    required IconData prefix,
    String? Function(String?)? validator,
    bool obscureText = false,
    Widget? suffix,
  }) {
    return SizedBox(
      height: 50.h,
      child: TextFormField(
        controller: controller,
        validator: validator,
        obscureText: obscureText,
        style: TextStyle(
          color: _textLight,
          fontSize: 13.sp,
          fontWeight: FontWeight.w400,
        ),
        cursorColor: _gold,
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: TextStyle(color: _textMuted, fontSize: 12.sp),
          prefixIcon: Icon(prefix, color: _gold, size: 16.w),
          suffixIcon: suffix,
          filled: true,
          fillColor: _inputFill,
          contentPadding: EdgeInsets.only(left: 0, right: 10.w, top: 12.h, bottom: 12.h),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide(color: _gold.withValues(alpha: 0.15), width: 0.5.w),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide(color: _gold.withValues(alpha: 0.45), width: 1.w),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide(color: Colors.red.shade300, width: 1.w),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide(color: Colors.red.shade400, width: 1.w),
          ),
          errorStyle: TextStyle(fontSize: 12.sp, color: Colors.red.shade300),
        ),
      ),
    );
  }

  Widget _buildSkipEntry() {
    return GestureDetector(
      onTap: () => Get.offAllNamed(AppRoutes.home),
      child: Text(
        '跳过登录，先去逛逛',
        style: TextStyle(
          fontSize: 14.sp,
          color: _textLight.withValues(alpha: 0.75),
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  Widget _buildServiceEntry(LoginController c) {
    return GestureDetector(
      onTap: c.showContactAdminTip,
      child: Text(
        '联系客服',
        style: TextStyle(
          fontSize: 16.sp,
          color: _goldDark,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _LoginContentLayoutDelegate extends SingleChildLayoutDelegate {
  const _LoginContentLayoutDelegate({required this.keyboardOcclusion});

  static const double _restingAlignmentY = 0.12;

  final double keyboardOcclusion;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final availableHeight = constraints.maxHeight > keyboardOcclusion ? constraints.maxHeight - keyboardOcclusion : 0.0;
    return BoxConstraints(
      minWidth: constraints.maxWidth,
      maxWidth: constraints.maxWidth,
      maxHeight: availableHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final restingSpace = size.height - childSize.height;
    final restingTop = restingSpace > 0 ? restingSpace * ((_restingAlignmentY + 1) / 2) : 0.0;
    final availableHeight = size.height > keyboardOcclusion ? size.height - keyboardOcclusion : 0.0;
    final bottomTop = availableHeight > childSize.height ? availableHeight - childSize.height : 0.0;
    // Stay at the resting position until the keyboard would overlap the form.
    // Tracking the inset continuously also prevents a rebound while it closes.
    final top = restingTop < bottomTop ? restingTop : bottomTop;

    return Offset((size.width - childSize.width) / 2, top);
  }

  @override
  bool shouldRelayout(_LoginContentLayoutDelegate oldDelegate) {
    return keyboardOcclusion != oldDelegate.keyboardOcclusion;
  }
}
