import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationDocumentsDirectory();
  Hive.init(dir.path);
  await Hive.openBox('notepad');
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Infinity Note',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: InfinityPage(),
    );
  }
}

class InfinityPage extends StatefulWidget {
  @override
  _InfinityPageState createState() => _InfinityPageState();
}

class _InfinityPageState extends State<InfinityPage> {
  final GlobalKey canvasKey = GlobalKey();
  List<Drawing> drawings = [];
  List<TextBox> texts = [];
  List<ImageBox> images = [];
  List<ShapeBox> shapes = [];
  List<StickyNote> notes = [];

  List<List<dynamic>> undoStack = [];
  List<List<dynamic>> redoStack = [];

  Color selectedColor = Colors.black;
  double strokeWidth = 3.0;
  bool isHighlighter = false;

  stt.SpeechToText speech = stt.SpeechToText();
  String speechText = "";

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    var box = Hive.box('notepad');
    setState(() {
      drawings = (box.get('drawings', defaultValue: []) as List).cast<Drawing>();
      texts = (box.get('texts', defaultValue: []) as List).cast<TextBox>();
      images = (box.get('images', defaultValue: []) as List).cast<ImageBox>();
      shapes = (box.get('shapes', defaultValue: []) as List).cast<ShapeBox>();
      notes = (box.get('notes', defaultValue: []) as List).cast<StickyNote>();
    });
  }

  void _saveData() {
    var box = Hive.box('notepad');
    box.put('drawings', drawings);
    box.put('texts', texts);
    box.put('images', images);
    box.put('shapes', shapes);
    box.put('notes', notes);
  }

  void _undo() {
    if (drawings.isEmpty && texts.isEmpty && images.isEmpty && shapes.isEmpty && notes.isEmpty) return;
    redoStack.add([List.from(drawings), List.from(texts), List.from(images), List.from(shapes), List.from(notes)]);
    setState(() {
      if (drawings.isNotEmpty) drawings.removeLast();
      else if (texts.isNotEmpty) texts.removeLast();
      else if (images.isNotEmpty) images.removeLast();
      else if (shapes.isNotEmpty) shapes.removeLast();
      else if (notes.isNotEmpty) notes.removeLast();
      _saveData();
    });
  }

  void _redo() {
    if (redoStack.isEmpty) return;
    var last = redoStack.removeLast();
    setState(() {
      drawings = List.from(last[0]);
      texts = List.from(last[1]);
      images = List.from(last[2]);
      shapes = List.from(last[3]);
      notes = List.from(last[4]);
      _saveData();
    });
  }

  void _pickImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      Uint8List bytes = await image.readAsBytes();
      setState(() {
        images.add(ImageBox(data: bytes, position: Offset(100, 100), scale: 1.0, rotation: 0.0));
        _saveData();
      });
    }
  }

  void _addText() {
    setState(() {
      texts.add(TextBox(text: 'نص جديد', position: Offset(100, 100), style: TextStyle(color: Colors.black, fontSize: 18)));
      _saveData();
    });
  }

  void _addStickyNote() {
    setState(() {
      notes.add(StickyNote(text: 'ملاحظة', position: Offset(150, 150), color: Colors.yellow));
      _saveData();
    });
  }

  void _addShape(ShapeType type) {
    setState(() {
      shapes.add(ShapeBox(type: type, position: Offset(200, 200), size: Size(100, 100), color: selectedColor));
      _saveData();
    });
  }

  void _pickColor() async {
    Color color = selectedColor;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("اختر اللون"),
        content: BlockPicker(
          pickerColor: selectedColor,
          onColorChanged: (c) => color = c,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("إلغاء")),
          TextButton(onPressed: () => Navigator.pop(context), child: Text("تأكيد")),
        ],
      ),
    );
    setState(() {
      selectedColor = color;
    });
  }

  void _startSpeech() async {
    bool available = await speech.initialize();
    if (available) {
      speech.listen(onResult: (val) {
        setState(() {
          speechText = val.recognizedWords;
        });
      });
    }
  }

  void _stopSpeech() {
    speech.stop();
    if (speechText.isNotEmpty) {
      setState(() {
        texts.add(TextBox(text: speechText, position: Offset(100, 300), style: TextStyle(color: Colors.black, fontSize: 18)));
        speechText = "";
        _saveData();
      });
    }
  }

  void _shareCanvas() async {
    RenderRepaintBoundary boundary = canvasKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    ui.Image image = await boundary.toImage(pixelRatio: 3.0);
    ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData != null) {
      Uint8List pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/shared.png').writeAsBytes(pngBytes);
      await Share.shareFiles([file.path], text: 'صفحة من Infinity Note');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Infinity Note"),
        actions: [
          IconButton(icon: Icon(Icons.brush), onPressed: _pickColor),
          IconButton(icon: Icon(Icons.text_fields), onPressed: _addText),
          IconButton(icon: Icon(Icons.image), onPressed: _pickImage),
          IconButton(icon: Icon(Icons.sticky_note_2), onPressed: _addStickyNote),
          IconButton(icon: Icon(Icons.crop_square), onPressed: () => _addShape(ShapeType.Rectangle)),
          IconButton(icon: Icon(Icons.circle), onPressed: () => _addShape(ShapeType.Circle)),
          IconButton(icon: Icon(Icons.undo), onPressed: _undo),
          IconButton(icon: Icon(Icons.redo), onPressed: _redo),
          IconButton(icon: Icon(Icons.mic), onPressed: _startSpeech),
          IconButton(icon: Icon(Icons.stop), onPressed: _stopSpeech),
          IconButton(icon: Icon(Icons.share), onPressed: _shareCanvas),
        ],
      ),
      body: InteractiveViewer(
        boundaryMargin: EdgeInsets.all(1000),
        minScale: 0.1,
        maxScale: 5.0,
        child: GestureDetector(
          onPanStart: (details) {
            setState(() {
              drawings.add(Drawing(points: [details.localPosition], paint: Paint()
                ..color = isHighlighter ? selectedColor.withOpacity(0.4) : selectedColor
                ..strokeWidth = strokeWidth
                ..strokeCap = StrokeCap.round
                ..style = PaintingStyle.stroke));
              _saveData();
            });
          },
          onPanUpdate: (details) {
            setState(() {
              drawings.last.points.add(details.localPosition);
              _saveData();
            });
          },
          child: RepaintBoundary(
            key: canvasKey,
            child: Container(
              width: 3000,
              height: 3000,
              color: Colors.white,
              child: Stack(
                children: [
                  CustomPaint(size: Size(3000, 3000), painter: DrawingPainter(drawings: drawings)),
                  ...texts.map((t) => Positioned(
                        left: t.position.dx,
                        top: t.position.dy,
                        child: Draggable(
                          feedback: Material(child: Text(t.text, style: t.style)),
                          childWhenDragging: Container(),
                          onDragEnd: (details) {
                            setState(() {
                              t.position = details.offset;
                              _saveData();
                            });
                          },
                          child: Text(t.text, style: t.style),
                        ),
                      )),
                  ...images.map((img) => Positioned(
                        left: img.position.dx,
                        top: img.position.dy,
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            setState(() {
                              img.position += details.delta;
                              _saveData();
                            });
                          },
                          child: Transform.rotate(
                            angle: img.rotation,
                            child: Image.memory(img.data, width: 150 * img.scale, height: 150 * img.scale),
                          ),
                        ),
                      )),
                  ...shapes.map((s) => Positioned(
                        left: s.position.dx,
                        top: s.position.dy,
                        child: Container(
                          width: s.size.width,
                          height: s.size.height,
                          decoration: BoxDecoration(
                            color: s.color.withOpacity(0.3),
                            shape: s.type == ShapeType.Circle ? BoxShape.circle : BoxShape.rectangle,
                          ),
                        ),
                      )),
                  ...notes.map((n) => Positioned(
                        left: n.position.dx,
                        top: n.position.dy,
                        child: Draggable(
                          feedback: Material(
                              child: Container(padding: EdgeInsets.all(8), color: n.color, child: Text(n.text))),
                          childWhenDragging: Container(),
                          onDragEnd: (details) {
                            setState(() {
                              n.position = details.offset;
                              _saveData();
                            });
                          },
                          child: Container(padding: EdgeInsets.all(8), color: n.color, child: Text(n.text)),
                        ),
                      )),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Classes
class Drawing {
  List<Offset> points;
  Paint paint;
  Drawing({required this.points, required this.paint});
}

class TextBox {
  String text;
  Offset position;
  TextStyle style;
  TextBox({required this.text, required this.position, required this.style});
}

class ImageBox {
  Uint8List data;
  Offset position;
  double scale;
  double rotation;
  ImageBox({required this.data, required this.position, required this.scale, required this.rotation});
}

enum ShapeType { Rectangle, Circle }

class ShapeBox {
  ShapeType type;
  Offset position;
  Size size;
  Color color;
  ShapeBox({required this.type, required this.position, required this.size, required this.color});
}

class StickyNote {
  String text;
  Offset position;
  Color color;
  StickyNote({required this.text, required this.position, required this.color});
}

class DrawingPainter extends CustomPainter {
  final List<Drawing> drawings;
  DrawingPainter({required this.drawings});

  @override
  void paint(Canvas canvas, Size size) {
    for (var d in drawings) {
      for (int i = 0; i < d.points.length - 1; i++) {
        if (d.points[i] != null && d.points[i + 1] != null) {
          canvas.drawLine(d.points[i], d.points[i + 1], d.paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
