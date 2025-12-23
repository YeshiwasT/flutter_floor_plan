# Floor Plan Creator

A Flutter package for creating and editing floor plan blueprints with rooms, doors, and SVG export/import capabilities.

## Features

- 🏠 **Multiple Room Shapes**: Rectangle, L-shape, U-shape, T-shape, and Circular rooms
- ✏️ **Freehand Drawing**: Draw custom room shapes with pencil mode
- 🚪 **Door Management**: Add doors to rooms with automatic opening detection
- 🎨 **Color Customization**: Choose from a palette of colors for rooms
- 📐 **Room Manipulation**: Move, resize, and rotate rooms
- 📝 **Room Naming**: Edit room names and view dimensions
- 📊 **Area Calculation**: Automatic area calculation in m²
- 💾 **SVG Import/Export**: Load and save floor plans as SVG files
- 🌐 **Web Support**: Full support for web platform with file download

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  floor_plan_creator: ^1.0.0
```


## Usage

### Basic Usage

```dart
import 'package:floor_plan_creator/floor_plan_creator.dart';

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: FloorPlanEditor(),
      ),
    );
  }
}
```

### With Callbacks

```dart
FloorPlanEditor(
  onChanged: (rooms, doors) {
    // Handle changes to rooms or doors
    print('Rooms: ${rooms.length}, Doors: ${doors.length}');
  },
  onSave: (svgContent) {
    // Handle SVG save
    print('SVG content length: ${svgContent.length}');
  },
  initialRooms: [
    Room(
      id: 'room1',
      path: Path()..addRect(Rect.fromLTWH(0, 0, 200, 150)),
      name: 'Living Room',
    ),
  ],
  canvasColor: Colors.blue.shade50,
  showToolbar: true,
  showSidebars: true,
)
```

## API Reference

### FloorPlanEditor

Main widget for the floor plan editor.

**Properties:**
- `onChanged`: Callback when rooms or doors change
- `onSave`: Callback when save is triggered (receives SVG content)
- `initialRooms`: Initial list of rooms to load
- `initialDoors`: Initial list of doors to load
- `canvasColor`: Background color of the canvas
- `showToolbar`: Whether to show the top toolbar
- `showSidebars`: Whether to show the left and right sidebars

### Room

Represents a room in the floor plan.

**Properties:**
- `id`: Unique identifier
- `path`: Flutter Path object defining the room shape
- `fillColor`: Room fill color
- `name`: Room name
- `doorOpenings`: List of door opening paths

### Door

Represents a door in the floor plan.

**Properties:**
- `id`: Unique identifier
- `path`: Flutter Path object defining the door shape
- `rotation`: Rotation angle in degrees
- `roomId`: Reference to the room this door belongs to
- `edge`: Which edge the door is on ('top', 'bottom', 'left', 'right')

## Features in Detail

### Creating Rooms

1. **Predefined Shapes**: Click on shape buttons in the right sidebar (Square, L-shape, U-shape, T-shape, Circular)
2. **Freehand Drawing**: Click the "Walls" button to enable pencil mode, then drag to draw custom shapes

### Adding Doors

1. Select a room
2. Click "Add Door" in the right sidebar
3. Click on a border edge of the room to place the door

### Editing Rooms

- **Move**: Click and drag a room
- **Resize**: Click and drag the corner handles
- **Rotate**: Click the rotation button in the left sidebar
- **Change Color**: Click the color button or use the color palette
- **Rename**: Click on the room name in the contextual bar

### Import/Export

- **Open**: Click "Open" to load an SVG file
- **Save**: Click "Save" to export the floor plan as SVG

## Platform Support

- ✅ Web (full support with file download)
- ✅ Mobile (iOS/Android - SVG export limited)
- ✅ Desktop (Windows/Mac/Linux - SVG export limited)

## License

MIT License

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

