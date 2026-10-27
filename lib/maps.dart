import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';


class MapViewerEditorPage extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> noteRef;
  final ll.LatLng? initialLatLng;
  final double? initialZoom;
  final String? initialAddress;

  const MapViewerEditorPage({
    super.key,
    required this.noteRef,
    this.initialLatLng,
    this.initialZoom,
    this.initialAddress,
  });

  @override
  State<MapViewerEditorPage> createState() =>
      _MapViewerEditorPageState();
}

class _MapViewerEditorPageState extends State<MapViewerEditorPage> {
  final MapController _mapController = MapController();

  static const _worldCenter = ll.LatLng(0, 0);
  static const double _worldZoom = 1.5;

  ll.LatLng? _selected;
  double _zoom = _worldZoom;
  String _address = '';
  bool _saving = false;
  bool _searchingAddress = false;

  @override
  void initState() {
    super.initState();

    _selected = widget.initialLatLng;
    _zoom = widget.initialZoom ?? _worldZoom;
    _address = widget.initialAddress ?? '';

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _safeMove(
        _selected ?? _worldCenter,
        _selected == null ? _worldZoom : _zoom,
      );
    });
  }

  void _safeMove(ll.LatLng center, double zoom) {
    try {
      _mapController.move(center, zoom);
    } catch (_) {
      // O mapa pode ainda não estar pronto.
    }
  }

  Future<String> _reverseGeocode(ll.LatLng point) async {
    final uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/reverse',
      {
        'lat': point.latitude.toString(),
        'lon': point.longitude.toString(),
        'format': 'jsonv2',
        'addressdetails': '1',
      },
    );

    try {
      final response = await http.get(
        uri,
        headers: const {
          'User-Agent': 'FirebaseApp/1.0 (pedro0010@hotmail.com)',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data =
            jsonDecode(response.body) as Map<String, dynamic>;

        final address = data['display_name']?.toString();

        if (address != null && address.isNotEmpty) {
          return address;
        }

        return 'Endereço não encontrado.';
      }

      return 'Não foi possível buscar o endereço '
          '(HTTP ${response.statusCode}).';
    } catch (_) {
      return 'Erro de conexão ao buscar o endereço.';
    }
  }

  Future<void> _save() async {
    final selected = _selected;

    if (selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Selecione um ponto no mapa antes de salvar.',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final address = await _reverseGeocode(selected);

      await widget.noteRef.set(
        {
          'position': GeoPoint(
            selected.latitude,
            selected.longitude,
          ),
          'latitude': selected.latitude,
          'longitude': selected.longitude,
          'address': address,
          'zoom': _zoom,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;

      setState(() {
        _address = address;
        _saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Local salvo com sucesso.')),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      setState(() => _saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao salvar: $e')),
      );
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Limpar localização'),
        content: const Text(
          'Deseja remover a localização salva?',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            onPressed: () =>
                Navigator.pop(dialogContext, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await widget.noteRef.update({
        'position': FieldValue.delete(),
        'latitude': FieldValue.delete(),
        'longitude': FieldValue.delete(),
        'address': FieldValue.delete(),
        'zoom': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      setState(() {
        _selected = null;
        _address = '';
        _zoom = _worldZoom;
      });

      _safeMove(_worldCenter, _worldZoom);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Localização removida.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao remover: $e')),
      );
    }
  }

  Future<void> _searchAddress() async {
    final selected = _selected;

    if (selected == null || _searchingAddress) return;

    setState(() => _searchingAddress = true);

    final address = await _reverseGeocode(selected);

    if (!mounted) return;

    setState(() {
      _address = address;
      _searchingAddress = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final markers = _selected == null
        ? <Marker>[]
        : <Marker>[
            Marker(
              point: _selected!,
              width: 40,
              height: 40,
              child: const Icon(
                Icons.location_on,
                size: 40,
                color: Colors.red,
              ),
            ),
          ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Geolocalização'),
        actions: [
          IconButton(
            tooltip: 'Limpar localização',
            onPressed: _saving ? null : _clear,
            icon: const Icon(Icons.delete),
          ),
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.check),
            label: const Text('Salvar'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _selected ?? _worldCenter,
                initialZoom:
                    _selected == null ? _worldZoom : _zoom,
                onTap: (tapPosition, point) {
                  setState(() => _selected = point);
                },
                onPositionChanged: (camera, hasGesture) {
                  _zoom = camera.zoom;
                },
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.myapp',
                ),
                MarkerLayer(markers: markers),
              ],
            ),
          ),
          Material(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerLow,
            child: ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text(
                _address.isEmpty
                    ? 'Endereço ainda não definido.'
                    : _address,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: FilledButton.tonalIcon(
                onPressed: _selected == null ||
                        _saving ||
                        _searchingAddress
                    ? null
                    : _searchAddress,
                icon: _searchingAddress
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.search),
                label: const Text('Buscar endereço'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

