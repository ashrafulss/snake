import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const SnakeApp());
}

class SnakeApp extends StatelessWidget {
  const SnakeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Snake',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorSchemeSeed: Colors.green,
      useMaterial3: true,
      brightness: Brightness.dark,
    ),
    home: const SnakePage(),
  );
}

enum Status { idle, playing, paused, over }

class SnakePage extends StatefulWidget {
  const SnakePage({super.key});

  @override
  State<SnakePage> createState() => _SnakePageState();
}

class _SnakePageState extends State<SnakePage> with WidgetsBindingObserver, TickerProviderStateMixin {
  static const int cols = 20;
  int _rows = 35; // Dynamically updated based on screen height

  final _rng = Random();
  Timer? _timer;
  Timer? _bigFoodTimer; // Timer for big bonus ball expiration
  late AnimationController _bonusAnimController; // Animation for pulsing bonus ball

  List<Point<int>> _snake = [];
  Point<int> _food = const Point(5, 5);
  bool _isBigFood = false; // Tracks if current food is Big Food
  int _extraGrowthCount = 0; // Extra squares to grow from Big Food

  Point<int> _dir = const Point(1, 0);
  Point<int> _next = const Point(1, 0);
  Status _status = Status.idle;
  int _score = 0;
  int _best = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadBest();

    // Setup pulsing animation controller for the bonus ball
    _bonusAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    // Re-render frame on every animation tick only when big food is active
    _bonusAnimController.addListener(() {
      if (_isBigFood && _status == Status.playing) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _bigFoodTimer?.cancel();
    _bonusAnimController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _status == Status.playing) {
      _pause();
    }
  }

  Future<void> _loadBest() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _best = prefs.getInt('best') ?? 0);
  }

  Future<void> _saveBest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('best', _best);
  }

  void _start() {
    _bigFoodTimer?.cancel();
    final startY = _rows ~/ 2;
    _snake = [Point(10, startY), Point(9, startY), Point(8, startY)];
    _dir = const Point(1, 0);
    _next = _dir;
    _score = 0;
    _extraGrowthCount = 0;
    _isBigFood = false;
    _spawnFood();
    setState(() => _status = Status.playing);
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final ms = max(70, 180 - _score * 4);
    _timer = Timer.periodic(Duration(milliseconds: ms), (_) => _tick());
  }

  void _pause() {
    _timer?.cancel();
    _bigFoodTimer?.cancel();
    setState(() => _status = Status.paused);
  }

  void _resume() {
    setState(() => _status = Status.playing);
    _schedule();
    if (_isBigFood) {
      _startBigFoodTimer();
    }
  }

  void _spawnFood() {
    _bigFoodTimer?.cancel();
    Point<int> p;
    do {
      p = Point(_rng.nextInt(cols), _rng.nextInt(_rows));
    } while (_snake.contains(p));
    _food = p;

    _isBigFood = (_score > 0 && _score % 5 == 0 && !_isBigFood);

    if (_isBigFood) {
      _startBigFoodTimer();
    }
  }

  void _startBigFoodTimer() {
    _bigFoodTimer?.cancel();
    // Big food disappears (turns back to normal red food) after 10 seconds
    _bigFoodTimer = Timer(const Duration(seconds: 10), () {
      if (_status == Status.playing && _isBigFood) {
        setState(() {
          _isBigFood = false;
        });
      }
    });
  }

  void _tick() {
    _dir = _next;
    final head = _snake.first;

    // Wrap around walls using dynamic rows/cols
    final newX = (head.x + _dir.x + cols) % cols;
    final newY = (head.y + _dir.y + _rows) % _rows;
    final nh = Point<int>(newX, newY);

    if (_snake.contains(nh)) {
      _gameOver();
      return;
    }

    var ate = false;
    setState(() {
      _snake.insert(0, nh);
      if (nh == _food) {
        _bigFoodTimer?.cancel();
        if (_isBigFood) {
          _score += 10;
          _extraGrowthCount += 2; // Grows 3 squares total (1 normal + 2 extra)
        } else {
          _score += 1;
        }
        ate = true;
        _spawnFood();
      } else {
        if (_extraGrowthCount > 0) {
          _extraGrowthCount--;
        } else {
          _snake.removeLast();
        }
      }
    });
    if (ate) _schedule();
  }

  void _gameOver() {
    _timer?.cancel();
    _bigFoodTimer?.cancel();
    setState(() {
      _status = Status.over;
      if (_score > _best) {
        _best = _score;
        _saveBest();
      }
    });
  }

  void _onTap(Offset pos, Size size) {
    if (_status != Status.playing) return;
    Point<int> want;
    // Use _dir instead of _next so tap areas don't shift mid-turn
    if (_dir.y == 0) {
      want = pos.dy < size.height / 2 ? const Point(0, -1) : const Point(0, 1);
    } else {
      want = pos.dx < size.width / 2 ? const Point(-1, 0) : const Point(1, 0);
    }
    _turn(want);
  }

  void _turn(Point<int> want) {
    if (want.x == -_dir.x && want.y == -_dir.y) return;
    _next = want;
  }

  Widget _stat(String label, int value) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey)),
      const SizedBox(width: 8),
      Text('$value', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
    ],
  );

  Widget _overlay() {
    String title;
    String button;
    VoidCallback onPressed;
    switch (_status) {
      case Status.paused:
        title = 'Paused';
        button = 'Resume';
        onPressed = _resume;
        break;
      case Status.over:
        title = 'Game Over\nScore: $_score';
        button = 'Play Again';
        onPressed = _start;
        break;
      default:
        title = '';
        button = 'Start Game';
        onPressed = _start;
    }
    return Container(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            FilledButton(onPressed: onPressed, child: Text(button)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar with Score & Pause button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Text('🐍 ', style: TextStyle(fontSize: 20)),
                      _stat('Score', _score),
                      const SizedBox(width: 24),
                      _stat('Best', _best),
                    ],
                  ),
                  if (_status == Status.playing)
                    IconButton(
                      icon: const Icon(Icons.pause),
                      onPressed: _pause,
                    ),
                ],
              ),
            ),
            // Game Board filling remaining vertical and horizontal space
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cellSize = constraints.maxWidth / cols;
                  _rows = (constraints.maxHeight / cellSize).floor();

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => _onTap(d.localPosition, constraints.biggest),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CustomPaint(
                          painter: BoardPainter(
                            _snake,
                            _food,
                            cols,
                            _rows,
                            _isBigFood,
                            _bonusAnimController.value,
                          ),
                        ),
                        if (_status != Status.playing) _overlay(),
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

class BoardPainter extends CustomPainter {
  final List<Point<int>> snake;
  final Point<int> food;
  final int cols;
  final int rows;
  final bool isBigFood;
  final double animationValue;

  BoardPainter(
      this.snake,
      this.food,
      this.cols,
      this.rows,
      this.isBigFood,
      this.animationValue,
      );

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / cols;

    final dark = Paint()..color = const Color(0xFF1B2A1B);
    final light = Paint()..color = const Color(0xFF223322);
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        canvas.drawRect(
          Rect.fromLTWH(x * cell, y * cell, cell, cell),
          (x + y) % 2 == 0 ? dark : light,
        );
      }
    }

    // Draw Food (Animated Big Amber Food vs Normal Red Food)
    if (isBigFood) {
      // Pulsing radius calculation (animates smoothly between 0.65 and 0.85 of cell size)
      final pulsingRadius = cell * (0.65 + (0.20 * animationValue));
      final pulsingGlowRadius = cell * (0.80 + (0.25 * animationValue));

      // Outer pulsing glow effect
      canvas.drawCircle(
        Offset((food.x + 0.5) * cell, (food.y + 0.5) * cell),
        pulsingGlowRadius,
        Paint()..color = Colors.amber.withOpacity(0.3 + (0.2 * animationValue)),
      );
      // Inner pulsing core for big food
      canvas.drawCircle(
        Offset((food.x + 0.5) * cell, (food.y + 0.5) * cell),
        pulsingRadius,
        Paint()..color = Colors.amberAccent,
      );
    } else {
      canvas.drawCircle(
        Offset((food.x + 0.5) * cell, (food.y + 0.5) * cell),
        cell * 0.38,
        Paint()..color = Colors.redAccent,
      );
    }

    // Draw Snake
    for (var i = 0; i < snake.length; i++) {
      final p = snake[i];
      final rect = Rect.fromLTWH(p.x * cell, p.y * cell, cell, cell).deflate(1.5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.3)),
        Paint()..color = i == 0 ? Colors.lightGreenAccent : Colors.green,
      );
    }
  }

  @override
  bool shouldRepaint(covariant BoardPainter old) =>
      old.isBigFood != isBigFood ||
          old.food != food ||
          old.snake != snake ||
          old.animationValue != animationValue;
}