import 'package:flutter/material.dart';

class SnowFoxErrorPage extends StatefulWidget {
  final String errorMessage;
  final VoidCallback? onRetry;

  const SnowFoxErrorPage({
    Key? key,
    this.errorMessage = "Something went wrong!",
    this.onRetry,
  }) : super(key: key);

  @override
  State<SnowFoxErrorPage> createState() => _SnowFoxErrorPageState();
}

class _SnowFoxErrorPageState extends State<SnowFoxErrorPage>
    with TickerProviderStateMixin {
  late AnimationController _legController;
  late AnimationController _bodyController;
  late AnimationController _tailController;
  late AnimationController _snowController;
  late AnimationController _earController;

  bool _showSnow = false;

  @override
  void initState() {
    super.initState();

    _legController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..repeat();

    _bodyController = AnimationController(
      duration: const Duration(milliseconds: 450),
      vsync: this,
    )..repeat();

    _tailController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..repeat();

    _snowController = AnimationController(
      duration: const Duration(seconds: 7),
      vsync: this,
    )..repeat();

    _earController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _legController.dispose();
    _bodyController.dispose();
    _tailController.dispose();
    _snowController.dispose();
    _earController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF9095B9),
      body: GestureDetector(
        onTap: () {
          setState(() {
            _showSnow = !_showSnow;
          });
        },
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Fox Animation
              SizedBox(
                width: 470,
                height: 335,
                child: Stack(
                  children: [
                    // Shadow
                    Positioned(
                      bottom: -10,
                      left: 47,
                      child: Container(
                        width: 376,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(100),
                        ),
                      ),
                    ),

                    // Front Legs
                    _buildLeg(127, 0, 0),
                    _buildLeg(127, 0.5, 0),

                    // Hind Legs
                    _buildHindLeg(263, 0.25, 0),
                    _buildHindLeg(263, 0.75, 0),

                    // Body
                    _buildBody(),

                    // Snow Effect
                    if (_showSnow) _buildSnow(),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // Error Text
              Text(
                widget.errorMessage,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 20),

              // Retry Button
              if (widget.onRetry != null)
                ElevatedButton(
                  onPressed: widget.onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF9095B9),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                  child: const Text(
                    'Try Again',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

              const SizedBox(height: 20),

              // Tap hint
              const Text(
                'Tap the fox for snow! ❄️',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeg(double right, double delay, int zIndex) {
    return AnimatedBuilder(
      animation: _legController,
      builder: (context, child) {
        final legOuterValue = Tween<double>(begin: 0, end: -76)
            .animate(CurvedAnimation(
          parent: _legController,
          curve: Interval(delay, delay + 0.5, curve: Curves.ease),
        ));

        final legUpValue = Tween<double>(begin: 0, end: -20)
            .animate(CurvedAnimation(
          parent: _legController,
          curve: Interval(delay + 0.25, delay + 0.75, curve: Curves.ease),
        ));

        return Positioned(
          bottom: 0,
          right: right,
          child: Transform.translate(
            offset: Offset(legOuterValue.value, legUpValue.value),
            child: SizedBox(
              width: 10,
              height: 56,
              child: Stack(
                children: [
                  // Paw
                  Positioned(
                    bottom: 0,
                    child: Container(
                      width: 10,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),

                  // Log (upper leg)
                  Positioned(
                    bottom: 7,
                    child: Container(
                      width: 10,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(5),
                          topRight: Radius.circular(5),
                        ),
                      ),
                    ),
                  ),

                  // Log inner (fox leg color)
                  Positioned(
                    bottom: 8,
                    child: Container(
                      width: 15,
                      height: 65,
                      decoration: BoxDecoration(
                        color: zIndex == 0 ? const Color(0xFFE2DEE8) : const Color(0xFFC7C3D0),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(5),
                          bottomRight: Radius.circular(5),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHindLeg(double right, double delay, int zIndex) {
    return AnimatedBuilder(
      animation: _legController,
      builder: (context, child) {
        final legOuterValue = Tween<double>(begin: 0, end: -76)
            .animate(CurvedAnimation(
          parent: _legController,
          curve: Interval(delay, delay + 0.5, curve: Curves.ease),
        ));

        final legUpValue = Tween<double>(begin: 0, end: -20)
            .animate(CurvedAnimation(
          parent: _legController,
          curve: Interval(delay + 0.25, delay + 0.75, curve: Curves.ease),
        ));

        return Positioned(
          bottom: 0,
          right: right,
          child: Transform.translate(
            offset: Offset(legOuterValue.value, legUpValue.value),
            child: SizedBox(
              width: 10,
              height: 92,
              child: Stack(
                children: [
                  // Hind Paw
                  Positioned(
                    bottom: 0,
                    child: Container(
                      width: 10,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),

                  // Hind Log inner
                  Positioned(
                    bottom: 7,
                    child: Container(
                      width: 15,
                      height: 80,
                      decoration: BoxDecoration(
                        color: zIndex == 0 ? const Color(0xFFE2DEE8) : const Color(0xFFC7C3D0),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody() {
    return AnimatedBuilder(
      animation: _bodyController,
      builder: (context, child) {
        final bodyRotation = Tween<double>(begin: -0.017, end: 0.017)
            .animate(_bodyController);

        return Positioned(
          top: 122.5,
          left: 170,
          child: Transform.rotate(
            angle: bodyRotation.value,
            child: Container(
              width: 173,
              height: 90,
              decoration: const BoxDecoration(
                color: Color(0xFFE2DEE8),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.elliptical(43, 45),
                  bottomLeft: Radius.elliptical(43, 45),
                  bottomRight: Radius.elliptical(43, 45),
                ),
              ),
              child: Stack(
                children: [
                  // Neck connection
                  Positioned(
                    top: -3,
                    right: 3,
                    child: Transform.rotate(
                      angle: 0.26,
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE2DEE8),
                          borderRadius: BorderRadius.only(
                            topRight: Radius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Head
                  _buildHead(),

                  // Tail
                  _buildTail(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHead() {
    return AnimatedBuilder(
      animation: _bodyController,
      builder: (context, child) {
        final headMovement = Tween<Offset>(begin: Offset.zero, end: const Offset(0, 2))
            .animate(_bodyController);

        return Positioned(
          bottom: 80,
          left: 112,
          child: Transform.translate(
            offset: headMovement.value,
            child: Container(
              width: 112,
              height: 87,
              decoration: const BoxDecoration(
                color: Color(0xFFE2DEE8),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.elliptical(45, 52),
                  topRight: Radius.elliptical(67, 17),
                ),
              ),
              child: Stack(
                children: [
                  // Ears
                  _buildEars(),

                  // Face
                  _buildFace(),

                  // Snout
                  _buildSnout(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEars() {
    return AnimatedBuilder(
      animation: _earController,
      builder: (context, child) {
        final earMovement = Tween<double>(begin: 0, end: -1)
            .animate(_earController);

        return Positioned(
          top: 10,
          left: 35,
          child: SizedBox(
            width: 60,
            height: 46,
            child: Stack(
              children: [
                // Left ear
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: Transform.translate(
                    offset: Offset(earMovement.value, 0),
                    child: Container(
                      width: 40,
                      height: 46,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE2DEE8),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.elliptical(40, 46),
                        ),
                      ),
                      child: Positioned(
                        right: 0,
                        child: Container(
                          width: 24,
                          height: 46,
                          decoration: const BoxDecoration(
                            color: Color(0xFFD5D1DC),
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.elliptical(24, 46),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Right ear
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 40,
                    height: 46,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE2DEE8),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.elliptical(40, 46),
                      ),
                    ),
                    child: Positioned(
                      right: 0,
                      child: Container(
                        width: 24,
                        height: 46,
                        decoration: const BoxDecoration(
                          color: Color(0xFFD5D1DC),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.elliptical(24, 46),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFace() {
    return AnimatedBuilder(
      animation: _bodyController,
      builder: (context, child) {
        final faceMovement = Tween<double>(begin: 0, end: -2)
            .animate(_bodyController);

        return Positioned(
          bottom: 0,
          right: 5,
          child: Transform.translate(
            offset: Offset(faceMovement.value, 0),
            child: Container(
              width: 84,
              height: 72,
              decoration: const BoxDecoration(
                color: Color(0xFFF0E9EC),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.elliptical(50, 72),
                  topRight: Radius.elliptical(34, 7),
                ),
              ),
              child: Stack(
                children: [
                  // Eye (line)
                  Positioned(
                    top: 13,
                    right: 10,
                    child: Transform.rotate(
                      angle: -0.21,
                      child: Container(
                        width: 25,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),

                  // Eye (dot)
                  Positioned(
                    top: 23,
                    right: 15,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSnout() {
    return AnimatedBuilder(
      animation: _bodyController,
      builder: (context, child) {
        final snoutScale = Tween<double>(begin: 1.0, end: 1.05)
            .animate(_bodyController);

        return Positioned(
          bottom: 0,
          right: -5,
          child: Transform.scale(
            scaleX: snoutScale.value,
            child: Container(
              width: 36,
              height: 24,
              decoration: const BoxDecoration(
                color: Color(0xFFF0E9EC),
                borderRadius: BorderRadius.only(
                  bottomRight: Radius.elliptical(36, 24),
                ),
              ),
              child: Stack(
                children: [
                  // Nose
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTail() {
    return AnimatedBuilder(
      animation: _tailController,
      builder: (context, child) {
        final tailRotation = Tween<double>(begin: -0.52, end: -0.42)
            .animate(_tailController);

        return Positioned(
          left: 10,
          top: 35,
          child: Transform.rotate(
            angle: tailRotation.value,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: Color(0xFFE2DEE8),
                shape: BoxShape.circle,
              ),
              child: Stack(
                children: [
                  // Tail segments with alternating colors
                  _buildTailSegment(36, 36, const Color(0xFFE2DEE8)),
                  _buildTailSegment(70, 70, const Color(0xFFE2DEE8)),
                  _buildTailSegment(93, 93, const Color(0xFFE2DEE8)),
                  _buildTailSegment(120, 120, const Color(0xFFF0E9EC)),
                  _buildTailSegment(98, 98, const Color(0xFFF0E9EC)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTailSegment(double width, double height, Color color) {
    return Positioned(
      right: width * 0.5,
      top: -height * 0.25,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  Widget _buildSnow() {
    return AnimatedBuilder(
      animation: _snowController,
      builder: (context, child) {
        return Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _showSnow ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 500),
              child: Stack(
                children: List.generate(50, (index) {
                  final double left = (index * 47) % 400;
                  final double animationOffset = (_snowController.value * 600) % 600;
                  final double top = (index * 23 + animationOffset) % 400;

                  return Positioned(
                    left: left,
                    top: top - 100,
                    child: Container(
                      width: 4 + (index % 3),
                      height: 4 + (index % 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.8),
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        );
      },
    );
  }
}

// Example usage:
class ErrorPageExample extends StatelessWidget {
  const ErrorPageExample({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: SnowFoxErrorPage(
        errorMessage: "Oops! Something went wrong.\nPlease try again.",
        onRetry: () {
          // Handle retry logic here
          print("Retry button pressed");
        },
      ),
    );
  }
}