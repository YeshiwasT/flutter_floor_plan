import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import '../models/room.dart';
import '../models/door.dart';
import '../models/resize_handle.dart';
import '../utils/path_utils.dart';
import '../utils/svg_parser.dart';
import '../utils/web_download_helper.dart';
import 'floor_painter.dart';

/// Main floor plan editor widget
class FloorPlanEditor extends StatefulWidget {
  /// Optional callback when rooms or doors change
  final Function(List<Room> rooms, List<Door> doors)? onChanged;
  
  /// Optional callback when save is triggered
  final Function(String svgContent)? onSave;
  
  /// Initial rooms to load
  final List<Room>? initialRooms;
  
  /// Initial doors to load
  final List<Door>? initialDoors;
  
  /// Canvas background color
  final Color? canvasColor;
  
  /// Show top toolbar
  final bool showToolbar;
  
  /// Show sidebars
  final bool showSidebars;

  const FloorPlanEditor({
    super.key,
    this.onChanged,
    this.onSave,
    this.initialRooms,
    this.initialDoors,
    this.canvasColor,
    this.showToolbar = true,
    this.showSidebars = true,
  });

  @override
  State<FloorPlanEditor> createState() => _FloorPlanEditorState();
}

class _FloorPlanEditorState extends State<FloorPlanEditor> {
  late List<Room> rooms;
  late List<Door> doors;
  Room? selectedRoom;
  Door? selectedDoor;

  Path? drawingPath;
  bool pencilMode = false;
  bool doorPlacementMode = false;

  Offset? lastPanPosition;
  ResizeHandle? activeHandle;
  Rect? startBounds;

  Color? selectedColor;
  int _roomCounter = 1;

  // Color palette
  static const List<Color> colorPalette = [
    Color(0xFF2196F3), // Blue
    Color(0xFF4CAF50), // Green
    Color(0xFFFF9800), // Orange
    Color(0xFF9C27B0), // Purple
    Color(0xFFF44336), // Red
    Color(0xFF00BCD4), // Cyan
    Color(0xFFFFEB3B), // Yellow
    Color(0xFF795548), // Brown
    Color(0xFF9E9E9E), // Grey
    Color(0xFFF5F5DC), // Beige (default)
  ];

  @override
  void initState() {
    super.initState();
    rooms = widget.initialRooms ?? [];
    doors = widget.initialDoors ?? [];
    _roomCounter = rooms.length + 1;
  }

  void _notifyChanged() {
    widget.onChanged?.call(rooms, doors);
  }

  String? _findNearestEdge(Offset pos, Room room) {
    final bounds = room.path.getBounds();
    const threshold = 15.0;

    final distToTop = (pos.dy - bounds.top).abs();
    final distToBottom = (pos.dy - bounds.bottom).abs();
    final distToLeft = (pos.dx - bounds.left).abs();
    final distToRight = (pos.dx - bounds.right).abs();

    final onTopEdge = distToTop < threshold &&
        pos.dx >= bounds.left &&
        pos.dx <= bounds.right;
    final onBottomEdge = distToBottom < threshold &&
        pos.dx >= bounds.left &&
        pos.dx <= bounds.right;
    final onLeftEdge = distToLeft < threshold &&
        pos.dy >= bounds.top &&
        pos.dy <= bounds.bottom;
    final onRightEdge = distToRight < threshold &&
        pos.dy >= bounds.top &&
        pos.dy <= bounds.bottom;

    if (onTopEdge &&
        distToTop <= distToBottom &&
        distToTop <= distToLeft &&
        distToTop <= distToRight) {
      return 'top';
    }
    if (onBottomEdge &&
        distToBottom <= distToTop &&
        distToBottom <= distToLeft &&
        distToBottom <= distToRight) {
      return 'bottom';
    }
    if (onLeftEdge &&
        distToLeft <= distToTop &&
        distToLeft <= distToBottom &&
        distToLeft <= distToRight) {
      return 'left';
    }
    if (onRightEdge &&
        distToRight <= distToTop &&
        distToRight <= distToBottom &&
        distToRight <= distToLeft) {
      return 'right';
    }

    return null;
  }

  void selectRoom(Offset pos) {
    if (doorPlacementMode && selectedRoom != null) {
      final edge = _findNearestEdge(pos, selectedRoom!);
      if (edge != null) {
        addDoorToRoomAtEdge(selectedRoom!, edge, pos);
        setState(() {
          doorPlacementMode = false;
        });
        return;
      }
    }

    for (final d in doors.reversed) {
      if (d.path.contains(pos)) {
        setState(() {
          selectedDoor = d;
          selectedRoom = null;
          activeHandle = null;
          doorPlacementMode = false;
        });
        return;
      }
    }

    for (final r in rooms.reversed) {
      final bounds = r.path.getBounds();
      final handle = PathUtils.hitTestHandle(pos, bounds);
      if (handle != null) {
        selectedRoom = r;
        selectedDoor = null;
        activeHandle = handle;
        startBounds = bounds;
        doorPlacementMode = false;
        setState(() {});
        return;
      }
      if (r.path.contains(pos)) {
        selectedRoom = r;
        selectedDoor = null;
        activeHandle = null;
        doorPlacementMode = false;
        setState(() {});
        return;
      }
    }
    setState(() {
      selectedRoom = null;
      selectedDoor = null;
      activeHandle = null;
      doorPlacementMode = false;
    });
  }

  void resizeRoom(Offset delta) {
    if (selectedRoom == null || activeHandle == null || startBounds == null)
      return;

    final bounds = startBounds!;
    double sx = 1, sy = 1;
    Offset anchor = bounds.center;

    if (activeHandle == ResizeHandle.bottomRight) {
      sx = (bounds.width + delta.dx) / bounds.width;
      sy = (bounds.height + delta.dy) / bounds.height;
      anchor = bounds.topLeft;
    } else if (activeHandle == ResizeHandle.topLeft) {
      sx = (bounds.width - delta.dx) / bounds.width;
      sy = (bounds.height - delta.dy) / bounds.height;
      anchor = bounds.bottomRight;
    } else if (activeHandle == ResizeHandle.topRight) {
      sx = (bounds.width + delta.dx) / bounds.width;
      sy = (bounds.height - delta.dy) / bounds.height;
      anchor = bounds.bottomLeft;
    } else if (activeHandle == ResizeHandle.bottomLeft) {
      sx = (bounds.width - delta.dx) / bounds.width;
      sy = (bounds.height + delta.dy) / bounds.height;
      anchor = bounds.topRight;
    }

    if (sx > 0.2 && sy > 0.2) {
      selectedRoom!.path = PathUtils.scalePath(selectedRoom!.path, sx, sy, anchor);
    }

    setState(() {
      _notifyChanged();
    });
  }

  void moveSelected(Offset delta) {
    if (selectedRoom != null) {
      setState(() {
        selectedRoom!.path = selectedRoom!.path.shift(delta);
        for (var i = 0; i < selectedRoom!.doorOpenings.length; i++) {
          selectedRoom!.doorOpenings[i] = selectedRoom!.doorOpenings[i].shift(delta);
        }
        for (final door in doors) {
          if (selectedRoom!.doorOpenings.any(
            (opening) =>
                (opening.getBounds().center - door.path.getBounds().center)
                    .distance <
                5,
          )) {
            door.path = door.path.shift(delta);
          }
        }
        _notifyChanged();
      });
    } else if (selectedDoor != null) {
      setState(() {
        selectedDoor!.path = selectedDoor!.path.shift(delta);
        _notifyChanged();
      });
    }
  }

  void rotateSelected() {
    if (selectedRoom != null) {
      final bounds = selectedRoom!.path.getBounds();
      setState(() {
        selectedRoom!.path = PathUtils.rotatePath(selectedRoom!.path, 90, bounds.center);
        for (var i = 0; i < selectedRoom!.doorOpenings.length; i++) {
          selectedRoom!.doorOpenings[i] = PathUtils.rotatePath(
            selectedRoom!.doorOpenings[i],
            90,
            bounds.center,
          );
        }
        for (final door in doors) {
          if (selectedRoom!.doorOpenings.any(
            (opening) =>
                (opening.getBounds().center - door.path.getBounds().center)
                    .distance <
                5,
          )) {
            door.path = PathUtils.rotatePath(door.path, 90, bounds.center);
            door.rotation = (door.rotation + 90) % 360;
          }
        }
        _notifyChanged();
      });
    } else if (selectedDoor != null) {
      final bounds = selectedDoor!.path.getBounds();
      setState(() {
        selectedDoor!.path = PathUtils.rotatePath(selectedDoor!.path, 90, bounds.center);
        selectedDoor!.rotation = (selectedDoor!.rotation + 90) % 360;
        _notifyChanged();
      });
    }
  }

  void addDoorToRoom(Room room) {
    setState(() {
      doorPlacementMode = true;
      selectedRoom = room;
    });
  }

  void addDoorToRoomAtEdge(Room room, String edge, Offset clickPos) {
    final bounds = room.path.getBounds();
    Offset doorCenter;
    Path doorPath;

    switch (edge) {
      case 'top':
        doorCenter = Offset(
          clickPos.dx.clamp(bounds.left + 25, bounds.right - 25),
          bounds.top,
        );
        doorPath = PathUtils.createDoor(doorCenter, width: 50, height: 12);
        break;
      case 'bottom':
        doorCenter = Offset(
          clickPos.dx.clamp(bounds.left + 25, bounds.right - 25),
          bounds.bottom,
        );
        doorPath = PathUtils.createDoor(doorCenter, width: 50, height: 12);
        break;
      case 'left':
        doorCenter = Offset(
          bounds.left,
          clickPos.dy.clamp(bounds.top + 25, bounds.bottom - 25),
        );
        doorPath = PathUtils.createDoor(doorCenter, width: 12, height: 50);
        break;
      case 'right':
        doorCenter = Offset(
          bounds.right,
          clickPos.dy.clamp(bounds.top + 25, bounds.bottom - 25),
        );
        doorPath = PathUtils.createDoor(doorCenter, width: 12, height: 50);
        break;
      default:
        return;
    }

    setState(() {
      room.path = PathUtils.cutDoorFromRoom(room.path, doorPath);
      room.doorOpenings.add(doorPath);
      doors.add(
        Door(
          id: UniqueKey().toString(),
          path: doorPath,
          roomId: room.id,
          edge: edge,
        ),
      );
      _notifyChanged();
    });
  }

  Future<void> _openSVG() async {
    try {
      FilePickerResult? result;

      if (kIsWeb) {
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['svg'],
          withData: true,
        );
      } else {
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['svg'],
        );
      }

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.single;
        String svgContent;

        if (kIsWeb) {
          if (file.bytes != null) {
            svgContent = String.fromCharCodes(file.bytes!);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Error: Could not read file data'),
                duration: Duration(seconds: 2),
              ),
            );
            return;
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('File opening is currently only available on web'),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }

        final parseResult = SvgParser.loadFromSVG(svgContent);
        setState(() {
          rooms.clear();
          doors.clear();
          rooms.addAll(parseResult['rooms'] as List<Room>);
          doors.addAll(parseResult['doors'] as List<Door>);
          selectedRoom = null;
          selectedDoor = null;
          _roomCounter = parseResult['roomCounter'] as int;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Floor plan loaded successfully'),
            duration: Duration(seconds: 2),
          ),
        );
        _notifyChanged();
      }
    } catch (e) {
      debugPrint('Error opening file: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error opening file: ${e.toString()}'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _downloadSVG() {
    if (rooms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No rooms to export'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    try {
      final svgContent = SvgParser.generateSVG(rooms, doors);
      widget.onSave?.call(svgContent);

      if (kIsWeb) {
        final helper = WebDownloadHelper();
        helper.downloadSVG(svgContent, 'floor_plan.svg');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Floor plan downloaded as SVG'),
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SVG export is currently only available on web'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error generating SVG: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error exporting SVG: ${e.toString()}'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: Row(
        children: [
          if (widget.showSidebars) _leftSidebar(),
          Expanded(
            child: Column(
              children: [
                if (widget.showToolbar) _topBar(),
                if (selectedRoom != null || selectedDoor != null)
                  _contextualBar(),
                if (doorPlacementMode && selectedRoom != null)
                  Container(
                    height: 40,
                    color: Colors.orange.shade100,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.orange),
                        const SizedBox(width: 8),
                        const Text(
                          "Click on a border edge to place the door",
                          style: TextStyle(color: Colors.orange),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              doorPlacementMode = false;
                            });
                          },
                          child: const Text("Cancel"),
                        ),
                      ],
                    ),
                  ),
                if (pencilMode)
                  Container(
                    height: 40,
                    color: Colors.blue.shade100,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Icon(Icons.edit, color: Colors.blue),
                        const SizedBox(width: 8),
                        const Text(
                          "Draw mode active - Drag to draw walls/rooms",
                          style: TextStyle(color: Colors.blue),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              pencilMode = false;
                              drawingPath = null;
                            });
                          },
                          child: const Text("Cancel"),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Container(
                    color: widget.canvasColor ?? const Color(0xFFE3F2FD),
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4,
                      child: GestureDetector(
                        onTapDown: (d) {
                          if (!pencilMode) {
                            selectRoom(d.localPosition);
                          } else {
                            if (doorPlacementMode) {
                              setState(() {
                                doorPlacementMode = false;
                              });
                            }
                          }
                        },
                        onPanStart: (d) {
                          lastPanPosition = d.localPosition;
                          if (pencilMode) {
                            drawingPath = Path()
                              ..moveTo(d.localPosition.dx, d.localPosition.dy);
                          }
                        },
                        onPanUpdate: (d) {
                          if (pencilMode) {
                            setState(() {
                              drawingPath!.lineTo(
                                d.localPosition.dx,
                                d.localPosition.dy,
                              );
                            });
                          } else if (activeHandle != null) {
                            resizeRoom(d.delta);
                          } else if (selectedRoom != null ||
                              selectedDoor != null) {
                            moveSelected(d.delta);
                          }
                        },
                        onPanEnd: (d) {
                          activeHandle = null;
                          startBounds = null;
                          if (pencilMode && drawingPath != null) {
                            setState(() {
                              final closedPath = Path.from(drawingPath!)
                                ..close();
                              rooms.add(
                                Room(
                                  id: UniqueKey().toString(),
                                  path: closedPath,
                                  fillColor:
                                      selectedColor ?? const Color(0xFFF5F5DC),
                                  name: 'Room $_roomCounter',
                                ),
                              );
                              _roomCounter++;
                              drawingPath = null;
                              _notifyChanged();
                            });
                          }
                        },
                        child: CustomPaint(
                          size: const Size(2000, 2000),
                          painter: FloorPainter(
                            rooms: rooms,
                            doors: doors,
                            selectedRoom: selectedRoom,
                            selectedDoor: selectedDoor,
                            previewPath: drawingPath,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (widget.showSidebars) _rightSidebar(),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Container(
      height: 56,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Text(
            "New project",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 8),
          const Text(
            "Ground floor",
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () {
              setState(() {
                rooms.clear();
                doors.clear();
                selectedRoom = null;
                selectedDoor = null;
                _roomCounter = 1;
                _notifyChanged();
              });
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text("New"),
            style: TextButton.styleFrom(foregroundColor: Colors.blue),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => _openSVG(),
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text("Open"),
            style: TextButton.styleFrom(foregroundColor: Colors.blue),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => _downloadSVG(),
            icon: const Icon(Icons.save, size: 18),
            label: const Text("Save"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _contextualBar() {
    String itemName = selectedRoom != null ? selectedRoom!.name : "Door";
    String dimensions = "";

    if (selectedRoom != null) {
      final bounds = selectedRoom!.path.getBounds();
      dimensions =
          "${bounds.width.toStringAsFixed(0)} cm × ${bounds.height.toStringAsFixed(0)} cm";
    } else if (selectedDoor != null) {
      final bounds = selectedDoor!.path.getBounds();
      dimensions =
          "${bounds.width.toStringAsFixed(0)} cm × ${bounds.height.toStringAsFixed(0)} cm";
    }

    return Container(
      height: 48,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          if (selectedRoom != null)
            GestureDetector(
              onTap: () => _showNameEditor(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      itemName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.edit, size: 14, color: Colors.grey),
                  ],
                ),
              ),
            )
          else
            Text(
              itemName,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          const SizedBox(width: 8),
          Text(
            dimensions,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          if (selectedRoom != null) ...[
            const SizedBox(width: 16),
            GestureDetector(
              onTap: () => _showColorPicker(context),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: selectedRoom!.fillColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey, width: 1),
                ),
              ),
            ),
          ],
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () {
              setState(() {
                selectedRoom = null;
                selectedDoor = null;
              });
            },
          ),
          if (selectedRoom != null)
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              onPressed: () => _showNameEditor(context),
            ),
        ],
      ),
    );
  }

  void _showNameEditor(BuildContext context) {
    if (selectedRoom == null) return;

    final controller = TextEditingController(text: selectedRoom!.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Room Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter room name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              setState(() {
                selectedRoom!.name = value.trim();
                _notifyChanged();
              });
              Navigator.of(context).pop();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  selectedRoom!.name = controller.text.trim();
                  _notifyChanged();
                });
                Navigator.of(context).pop();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _leftSidebar() {
    return Container(
      width: 64,
      color: Colors.white,
      child: Column(
        children: [
          const SizedBox(height: 24),
          const SizedBox(height: 20),
          _sidebarButton(Icons.add, "New", () {
            setState(() {
              rooms.clear();
              doors.clear();
              selectedRoom = null;
              selectedDoor = null;
              _roomCounter = 1;
              _notifyChanged();
            });
          }),
          _sidebarButton(Icons.folder_open, "Open", () => _openSVG()),
          _sidebarButton(Icons.clear_all_outlined, "Clear All", () {
            setState(() {
              rooms.clear();
              doors.clear();
              selectedRoom = null;
              selectedDoor = null;
              drawingPath = null;
              pencilMode = false;
              doorPlacementMode = false;
              lastPanPosition = null;
              activeHandle = null;
              startBounds = null;
              selectedColor = null;
              _roomCounter = 1;
              _notifyChanged();
            });
          }),
          _sidebarButton(Icons.save, "Save", () => _downloadSVG()),
          const Divider(),
          _sidebarButton(Icons.delete, "Delete", () {
            if (selectedRoom != null) {
              setState(() {
                rooms.remove(selectedRoom);
                selectedRoom = null;
                _notifyChanged();
              });
            } else if (selectedDoor != null) {
              setState(() {
                doors.remove(selectedDoor);
                selectedDoor = null;
                _notifyChanged();
              });
            }
          }),
          _sidebarButton(Icons.rotate_right, "Rotation", rotateSelected),
          _sidebarButton(Icons.palette, "Color", () {
            if (selectedRoom != null) {
              _showColorPicker(context);
            }
          }),
        ],
      ),
    );
  }

  Widget _sidebarButton(IconData icon, String tooltip, VoidCallback onPressed) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon),
        onPressed: onPressed,
        tooltip: tooltip,
      ),
    );
  }

  Widget _rightSidebar() {
    return Container(
      width: 200,
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: const Text(
              "Colors",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: colorPalette.map((color) {
                final isSelected = selectedColor == color;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedColor = color;
                      if (selectedRoom != null) {
                        selectedRoom!.fillColor = color;
                        _notifyChanged();
                      }
                    });
                  },
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.black : Colors.grey,
                        width: isSelected ? 3 : 1,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(),
          Container(
            padding: const EdgeInsets.all(16),
            child: const Text(
              "Structure",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              padding: const EdgeInsets.all(8),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                _structureButton(Icons.crop_square, "Square room", () {
                  setState(() {
                    rooms.add(
                      Room(
                        id: UniqueKey().toString(),
                        path: PathUtils.createRectangle(const Offset(200, 200)),
                        fillColor: selectedColor ?? const Color(0xFFF5F5DC),
                        name: 'Room $_roomCounter',
                      ),
                    );
                    _roomCounter++;
                    _notifyChanged();
                  });
                }),
                _structureButton(Icons.crop_square, "L-shape room", () {
                  setState(() {
                    rooms.add(
                      Room(
                        id: UniqueKey().toString(),
                        path: PathUtils.createLShape(const Offset(200, 200)),
                        fillColor: selectedColor ?? const Color(0xFFF5F5DC),
                        name: 'Room $_roomCounter',
                      ),
                    );
                    _roomCounter++;
                    _notifyChanged();
                  });
                }),
                _structureButton(Icons.account_tree, "U-shape room", () {
                  setState(() {
                    rooms.add(
                      Room(
                        id: UniqueKey().toString(),
                        path: PathUtils.createUShape(const Offset(200, 200)),
                        fillColor: selectedColor ?? const Color(0xFFF5F5DC),
                        name: 'Room $_roomCounter',
                      ),
                    );
                    _roomCounter++;
                    _notifyChanged();
                  });
                }),
                _structureButton(Icons.call_split, "T-shape room", () {
                  setState(() {
                    rooms.add(
                      Room(
                        id: UniqueKey().toString(),
                        path: PathUtils.createTShape(const Offset(200, 200)),
                        fillColor: selectedColor ?? const Color(0xFFF5F5DC),
                        name: 'Room $_roomCounter',
                      ),
                    );
                    _roomCounter++;
                    _notifyChanged();
                  });
                }),
                _structureButton(Icons.circle, "Circular room", () {
                  setState(() {
                    rooms.add(
                      Room(
                        id: UniqueKey().toString(),
                        path: PathUtils.createCircle(const Offset(200, 200), radius: 100),
                        fillColor: selectedColor ?? const Color(0xFFF5F5DC),
                        name: 'Room $_roomCounter',
                      ),
                    );
                    _roomCounter++;
                    _notifyChanged();
                  });
                }),
                _structureButton(Icons.edit, "Walls", () {
                  setState(() {
                    pencilMode = !pencilMode;
                    if (!pencilMode) {
                      drawingPath = null;
                      doorPlacementMode = false;
                    }
                  });
                }, isSelected: pencilMode),
                _structureButton(Icons.meeting_room, "Add Door", () {
                  if (selectedRoom != null) {
                    addDoorToRoom(selectedRoom!);
                  }
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showColorPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Room Color'),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: colorPalette.map((color) {
            final isSelected = selectedRoom?.fillColor == color;
            return GestureDetector(
              onTap: () {
                if (selectedRoom != null) {
                  setState(() {
                    selectedRoom!.fillColor = color;
                    selectedColor = color;
                    _notifyChanged();
                  });
                }
                Navigator.of(context).pop();
              },
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? Colors.black : Colors.grey,
                    width: isSelected ? 3 : 1,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white)
                    : null,
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _structureButton(
    IconData icon,
    String label,
    VoidCallback onPressed, {
    bool isSelected = false,
  }) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade50 : Colors.transparent,
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: isSelected ? Colors.blue : null),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isSelected ? Colors.blue : null,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
