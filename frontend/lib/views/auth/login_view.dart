import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/motion_preference_native.dart'
    if (dart.library.html) '../../core/utils/motion_preference_web.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/ui_effects.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView>
    with SingleTickerProviderStateMixin {
  bool _isSignUpMode = false;
  final _videoBackgroundKey = GlobalKey<_LoginVideoBackgroundState>();
  final _browserMotion = MotionPreference();
  bool get _reduceMotion =>
      MediaQuery.disableAnimationsOf(context) || _browserMotion.value;
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  );

  // Sign In Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = true;

  // Sign Up Controllers
  final _regNameController = TextEditingController();
  final _regEmailController = TextEditingController();
  final _regPasswordController = TextEditingController();
  int? _regDeptId;
  bool _obscureRegPassword = true;
  List<Map<String, dynamic>> _departments = [];
  bool _departmentsLoading = false;

  @override
  void initState() {
    super.initState();
    _browserMotion.addListener(_motionPreferenceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDepartments();
      _prefillRememberedEmail();
    });
  }

  void _prefillRememberedEmail() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    void apply() {
      final email = auth.rememberedEmail;
      if (email != null && email.isNotEmpty && _emailController.text.isEmpty) {
        _emailController.text = email;
      }
    }

    if (auth.rememberedEmail != null) {
      apply();
      return;
    }
    // initAuth() loads prefs asynchronously, so wait for the first notify.
    void listener() {
      if (!mounted) {
        auth.removeListener(listener);
        return;
      }
      apply();
      auth.removeListener(listener);
    }

    auth.addListener(listener);
  }

  void _motionPreferenceChanged() {
    _syncAmbientMotion();
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAmbientMotion();
  }

  void _syncAmbientMotion() {
    if (_reduceMotion) {
      _ambient.stop();
    } else if (!_ambient.isAnimating) {
      _ambient.repeat();
    }
  }

  Future<void> _loadDepartments() async {
    if (_departmentsLoading) return;
    setState(() => _departmentsLoading = true);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final result = await auth.fetchPublicDepartments();
    if (!mounted) return;
    setState(() {
      _departments = result;
      _departmentsLoading = false;
      if (_regDeptId == null && result.isNotEmpty) {
        _regDeptId = (result.first['id'] as num).toInt();
      }
    });
  }

  @override
  void dispose() {
    _browserMotion.dispose();
    _ambient.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _regNameController.dispose();
    _regEmailController.dispose();
    _regPasswordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showToast('Please enter both email and password', isError: true);
      return;
    }

    final success =
        await auth.login(email, password, rememberMe: _rememberMe);

    if (!success && mounted && auth.errorMessage != null) {
      _showToast(auth.errorMessage!, isError: true);
    }
  }

  void _handleRegister() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final name = _regNameController.text.trim();
    final email = _regEmailController.text.trim();
    final password = _regPasswordController.text;

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      _showToast('Please fill in all registration fields', isError: true);
      return;
    }

    if (!email.contains('@') || !email.contains('.')) {
      _showToast('Please enter a valid email address', isError: true);
      return;
    }

    if (password.length < 8 ||
        !password.contains(RegExp(r'[A-Za-z]')) ||
        !password.contains(RegExp(r'[0-9]'))) {
      _showToast(
          'Password must be at least 8 characters and contain letters and numbers',
          isError: true);
      return;
    }

    if (_regDeptId == null) {
      _showToast('Please select a department', isError: true);
      return;
    }

    final success = await auth.register(
      name: name,
      email: email,
      password: password,
      departmentId: _regDeptId,
    );

    if (success && mounted) {
      _showToast('Account created successfully! Welcome to KuhuGrantha.',
          isError: false);
    } else if (!success && mounted && auth.errorMessage != null) {
      _showToast(auth.errorMessage!, isError: true);
    }
  }

  void _showToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
                color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
                child: Text(message,
                    style: const TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
        backgroundColor: isError ? AppTheme.danger : AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _videoBackgroundKey.currentState?.ensurePlaying(),
        child: Stack(
          children: [
            // Full-screen looping brand film
            Positioned.fill(
              child: _LoginVideoBackground(key: _videoBackgroundKey),
            ),

            // Slow drifting ambient glow
            Positioned.fill(child: _buildAmbientBackground()),

            // Readability scrim over the film
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        const Color(0xFF05080F).withOpacity(0.82),
                        const Color(0xFF05080F).withOpacity(0.55),
                        const Color(0xFF05080F).withOpacity(0.78),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 960;
                  final compact =
                      constraints.maxWidth < 760 || constraints.maxHeight < 780;

                  return SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                        horizontal: compact ? 10 : 24,
                        vertical: compact ? 10 : 28),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: isWide ? 1080 : (compact ? 380 : 500),
                          minHeight: constraints.maxHeight >
                                  (compact ? 20 : 56)
                              ? constraints.maxHeight - (compact ? 20 : 56)
                              : 0,
                        ),
                        child: isWide
                            ? _buildWideLayout(auth)
                            : _buildNarrowLayout(auth),
                      ),
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

  // Desktop 2-column layout (perfect balance)
  Widget _buildWideLayout(AuthProvider auth) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Left Column: Branding + 1-Click Access
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.only(right: 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeSlideIn(child: _buildBrandHeader()),
              ],
            ),
          ),
        ),

        // Right Column: Auth Card (Sign In / Sign Up)
        Expanded(
          flex: 5,
          child: FadeSlideIn(
              delay: const Duration(milliseconds: 100),
              offsetY: 30,
              child: _buildAuthCard(auth)),
        ),
      ],
    );
  }

  // Tablet / Mobile single column layout
  Widget _buildNarrowLayout(AuthProvider auth) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 760 || size.height < 780;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(height: compact ? 2 : 12),
        FadeSlideIn(child: _buildBrandHeader()),
        SizedBox(height: compact ? 10 : 24),
        FadeSlideIn(
            delay: const Duration(milliseconds: 100),
            child: _buildAuthCard(auth)),
        SizedBox(height: compact ? 10 : 24),
        const Text(
          '© 2026 KuhuGrantha Pvt Ltd (KGPL). All Rights Reserved.',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontSize: 12,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // Brand header widget
  Widget _buildBrandHeader() {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 760 || size.height < 780;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'KuhuGrantha',
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 21 : 30,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Private Limited',
          style: TextStyle(
            color: const Color(0xFFD4AF37),
            fontSize: compact ? 12 : 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
          ),
        ),
        SizedBox(height: compact ? 6 : 12),
        _buildAnimatedPortalBadge(),
      ],
    );
  }

  Widget _buildAmbientBackground() {
    return AnimatedBuilder(
      animation: _ambient,
      builder: (context, _) {
        final double t = _ambient.value * 2 * math.pi;
        return Stack(
          children: [
            Positioned(
              top: -120 + 34 * math.sin(t),
              left: -120 + 46 * math.cos(t * 0.8),
              child: _glowOrb(
                size: 460 + 26 * math.sin(t * 1.3),
                color: const Color(0xFF2563EB),
                opacity: 0.13 + 0.05 * (0.5 + 0.5 * math.sin(t)),
              ),
            ),
            Positioned(
              bottom: -150 + 28 * math.cos(t * 1.1),
              right: -100 + 38 * math.sin(t * 0.7),
              child: _glowOrb(
                size: 560 + 32 * math.cos(t),
                color: const Color(0xFFD4AF37),
                opacity: 0.06 + 0.03 * (0.5 + 0.5 * math.cos(t * 1.4)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _glowOrb({
    required double size,
    required Color color,
    required double opacity,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withOpacity(opacity), color.withOpacity(0)],
        ),
      ),
    );
  }

  Widget _buildAnimatedPortalBadge() {
    return AnimatedBuilder(
      animation: _ambient,
      builder: (context, child) {
        final double t = _ambient.value * 2 * math.pi;
        final double shift = 0.35 * math.sin(t);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1 + shift, -1),
              end: Alignment(1 + shift, 1),
              colors: const [
                Color(0xFF1E3A8A),
                Color(0xFF2563EB),
                Color(0xFF1E3A8A),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.5)),
          ),
          child: child,
        );
      },
      child: const Text(
        'KGPL INTERN TRAINING & MANAGEMENT PORTAL',
        style: TextStyle(
          color: Color(0xFFE0E7FF),
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  // Unified Sign In / Sign Up Card
  Widget _buildAuthCard(AuthProvider auth) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 760 || size.height < 780;
    return Container(
      padding: EdgeInsets.all(compact ? 18 : 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(compact ? 14 : 20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Switcher between Sign In and Sign Up
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _isSignUpMode = false),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: EdgeInsets.symmetric(vertical: compact ? 7 : 10),
                      decoration: BoxDecoration(
                        color:
                            !_isSignUpMode ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: !_isSignUpMode
                            ? [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                )
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          'Sign In',
                          style: TextStyle(
                            fontSize: compact ? 12.5 : 14,
                            fontWeight: FontWeight.bold,
                            color: !_isSignUpMode
                                ? AppTheme.primaryNavy
                                : AppTheme.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _isSignUpMode = true),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: EdgeInsets.symmetric(vertical: compact ? 7 : 10),
                      decoration: BoxDecoration(
                        color:
                            _isSignUpMode ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: _isSignUpMode
                            ? [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                )
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          'Sign Up / Register',
                          style: TextStyle(
                            fontSize: compact ? 12.5 : 14,
                            fontWeight: FontWeight.bold,
                            color: _isSignUpMode
                                ? AppTheme.primaryNavy
                                : AppTheme.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: compact ? 12 : 24),

          if (!_isSignUpMode) ...[
            // Sign In View
            _buildSignInFields(auth),
          ] else ...[
            // Sign Up View
            _buildSignUpFields(auth),
          ],
        ],
      ),
    );
  }

  Widget _buildSignInFields(AuthProvider auth) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 760 || size.height < 780;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: compact ? 18 : 22,
              decoration: BoxDecoration(
                color: const Color(0xFFD4AF37),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Portal Sign In',
              style: TextStyle(
                fontSize: compact ? 17 : 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 4 : 6),
        Text(
          'Enter your credentials to access learning materials & dashboard.',
          style: TextStyle(
              fontSize: compact ? 12 : 13,
              color: AppTheme.textSecondary),
        ),
        SizedBox(height: compact ? 12 : 24),

        // Email Field
        Text(
          'Email Address',
          style: TextStyle(
              fontSize: compact ? 12.5 : 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary),
        ),
        SizedBox(height: compact ? 5 : 8),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            isDense: compact,
            contentPadding:
                compact ? const EdgeInsets.symmetric(vertical: 12) : null,
            prefixIcon: const Icon(Icons.mail_outline,
                size: 20, color: AppTheme.textMuted),
            hintText: 'name@kgpl.com',
            hintStyle: TextStyle(
                color: AppTheme.textMuted, fontSize: compact ? 13 : 14),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppTheme.primaryBlue, width: 2)),
          ),
        ),
        SizedBox(height: compact ? 10 : 16),

        // Password Field
        Text(
          'Password',
          style: TextStyle(
              fontSize: compact ? 12.5 : 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary),
        ),
        SizedBox(height: compact ? 5 : 8),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            isDense: compact,
            contentPadding:
                compact ? const EdgeInsets.symmetric(vertical: 12) : null,
            prefixIcon: const Icon(Icons.lock_outline,
                size: 20, color: AppTheme.textMuted),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20,
                color: AppTheme.textMuted,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
            hintText: '••••••••••••',
            hintStyle: TextStyle(
                color: AppTheme.textMuted, fontSize: compact ? 13 : 14),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppTheme.primaryBlue, width: 2)),
          ),
          onSubmitted: (_) => _handleLogin(),
        ),

        SizedBox(height: compact ? 2 : 6),

        // Remember me
        Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: _rememberMe,
                onChanged: (v) => setState(() => _rememberMe = v ?? false),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                activeColor: AppTheme.primaryBlue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _rememberMe = !_rememberMe),
                child: Text(
                  'Remember me on this device',
                  style: TextStyle(
                    fontSize: compact ? 12 : 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),

        SizedBox(height: compact ? 12 : 22),

        // Submit Button
        Container(
          height: compact ? 42 : 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2563EB).withOpacity(0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: auth.isLoading ? null : _handleLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: auth.isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Sign In to Dashboard',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.4),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildSignUpFields(AuthProvider auth) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 760 || size.height < 780;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: compact ? 18 : 22,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Create Account',
              style: TextStyle(
                fontSize: compact ? 17 : 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 4 : 6),
        Text(
          'Register as a new Intern to access training materials.',
          style: TextStyle(
              fontSize: compact ? 12 : 13,
              color: AppTheme.textSecondary),
        ),
        SizedBox(height: compact ? 12 : 18),

        // Full Name Field
        const Text(
          'Full Name',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary),
        ),
        SizedBox(height: compact ? 5 : 6),
        TextField(
          controller: _regNameController,
          decoration: InputDecoration(
            isDense: compact,
            contentPadding:
                compact ? const EdgeInsets.symmetric(vertical: 11) : null,
            prefixIcon: const Icon(Icons.person_outline,
                size: 20, color: AppTheme.textMuted),
            hintText: 'e.g. Rahul Sharma',
            hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFF10B981), width: 2)),
          ),
        ),
        SizedBox(height: compact ? 8 : 14),

        // Email Field
        const Text(
          'Email Address',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary),
        ),
        SizedBox(height: compact ? 5 : 6),
        TextField(
          controller: _regEmailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            isDense: compact,
            contentPadding:
                compact ? const EdgeInsets.symmetric(vertical: 11) : null,
            prefixIcon: const Icon(Icons.mail_outline,
                size: 20, color: AppTheme.textMuted),
            hintText: 'yourname@kgpl.com',
            hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFF10B981), width: 2)),
          ),
        ),
        SizedBox(height: compact ? 8 : 14),

        // Password Field
        const Text(
          'Password',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary),
        ),
        SizedBox(height: compact ? 5 : 6),
        TextField(
          controller: _regPasswordController,
          obscureText: _obscureRegPassword,
          decoration: InputDecoration(
            isDense: compact,
            contentPadding:
                compact ? const EdgeInsets.symmetric(vertical: 11) : null,
            prefixIcon: const Icon(Icons.lock_outline,
                size: 20, color: AppTheme.textMuted),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureRegPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20,
                color: AppTheme.textMuted,
              ),
              onPressed: () =>
                  setState(() => _obscureRegPassword = !_obscureRegPassword),
            ),
            hintText: 'At least 8 characters with letters and numbers',
            hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFF10B981), width: 2)),
          ),
        ),
        SizedBox(height: compact ? 8 : 14),

        // Department Selector
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Department',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              value: _regDeptId,
              items: _departments
                  .map((dept) => DropdownMenuItem<int>(
                        value: (dept['id'] as num).toInt(),
                        child: Text(dept['name']?.toString() ?? '',
                            style: const TextStyle(fontSize: 13)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _regDeptId = v),
              hint: Text(
                _departmentsLoading
                    ? 'Loading departments...'
                    : 'Select department',
                style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
              ),
              decoration: InputDecoration(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),

        SizedBox(height: compact ? 12 : 22),

        // Register Button
        Container(
          height: compact ? 42 : 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF10B981), Color(0xFF059669)],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF10B981).withOpacity(0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: auth.isLoading ? null : _handleRegister,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: auth.isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Create Account & Enter Portal',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.4),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _LoginVideoBackground extends StatefulWidget {
  const _LoginVideoBackground({super.key});

  @override
  State<_LoginVideoBackground> createState() => _LoginVideoBackgroundState();
}

class _LoginVideoBackgroundState extends State<_LoginVideoBackground>
    with WidgetsBindingObserver {
  VideoPlayerController _controller = _newController();
  static VideoPlayerController _newController() =>
      VideoPlayerController.asset('assets/videos/kuhugrantha-intro.mp4');
  bool _unavailable = false;
  bool _ready = false;
  int _initAttempts = 0;
  Timer? _autoplayRetry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_restartIfEnded);
    _initializeVideo();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ensurePlaying();
  }

  Future<void> _initializeVideo() async {
    _initAttempts += 1;
    try {
      await _controller.initialize();
      if (!mounted) return;
      await _controller.setLooping(true);
      if (!mounted) return;
      await _controller.setVolume(0);
      if (!mounted) return;
      setState(() => _ready = true);
      ensurePlaying();
      _scheduleAutoplayRetry();
    } catch (_) {
      if (!mounted) return;
      // First load can abort the asset request while the page settles; start
      // a fresh controller instead of falling back to the static logo.
      if (_initAttempts < 4) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (!mounted) return;
        _controller.removeListener(_restartIfEnded);
        _controller.dispose();
        _controller = _newController();
        _controller.addListener(_restartIfEnded);
        setState(() => _ready = false);
        await _initializeVideo();
        return;
      }
      setState(() => _unavailable = true);
    }
  }

  // Autoplay can be rejected until the page has focus or a user gesture.
  // Treat that as retryable instead of swapping in the fallback.
  void ensurePlaying() {
    if (_ready && !_controller.value.isPlaying) {
      _controller.play().catchError((_) {});
    }
  }

  // Some browsers drop the loop flag or stall on the last frame; restart
  // explicitly so the intro keeps playing while the sign-in page is open.
  void _restartIfEnded() {
    if (!_ready || _unavailable) return;
    final value = _controller.value;
    if (!value.isInitialized || value.duration <= Duration.zero) return;
    final atEnd =
        value.position >= value.duration - const Duration(milliseconds: 350);
    if (atEnd && !value.isPlaying) {
      _controller.seekTo(Duration.zero).then((_) {
        if (mounted) ensurePlaying();
      }).catchError((_) {});
    }
  }

  void _scheduleAutoplayRetry() {
    _autoplayRetry?.cancel();
    _autoplayRetry = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted || _unavailable) {
        timer.cancel();
        return;
      }
      if (_controller.value.isPlaying) {
        timer.cancel();
        return;
      }
      ensurePlaying();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoplayRetry?.cancel();
    _controller.removeListener(_restartIfEnded);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF090D16),
      child: ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: _controller,
        builder: (context, value, _) {
          if (_unavailable || !_ready || value.size.isEmpty) {
            return const SizedBox.expand();
          }
          return ExcludeSemantics(
            child: SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: value.size.width,
                  height: value.size.height,
                  child: VideoPlayer(_controller),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
