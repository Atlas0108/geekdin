import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/geocoding_service.dart';
import '../services/user_firestore.dart';
import '../widgets/firebase_profile_image.dart';

const int _maxProfilePhotos = 6;

/// Collects profile photos (Storage), city + coordinates, bio, and interests (Firestore).
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({
    required this.user,
    this.initialData,
    super.key,
  });

  final User user;
  final Map<String, dynamic>? initialData;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _bioController = TextEditingController();
  final _cityController = TextEditingController();
  final _interestController = TextEditingController();
  final _cityFocus = FocusNode();

  final List<String> _keptExistingImageUrls = [];
  final List<XFile> _newImages = [];
  final List<String> _interests = [];

  List<GeocodeSuggestion> _suggestions = [];
  Timer? _cityDebounce;
  double? _latitude;
  double? _longitude;
  bool _suppressCityListener = false;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final d = widget.initialData;
    if (d != null) {
      final bio = (d['bio'] as String?)?.trim();
      if (bio != null && bio.isNotEmpty) {
        _bioController.text = bio;
      }
      final city = (d['city'] as String?)?.trim();
      if (city != null && city.isNotEmpty) {
        _cityController.text = city;
      }
      final lat = d['latitude'];
      final lng = d['longitude'];
      if (lat is num && lng is num) {
        _latitude = lat.toDouble();
        _longitude = lng.toDouble();
      }
      final raw = d['interests'];
      if (raw is List) {
        for (final e in raw) {
          if (e is String && e.trim().isNotEmpty) {
            _interests.add(e.trim());
          }
        }
      }
      final urls = d['profileImageUrls'];
      if (urls is List) {
        for (final u in urls) {
          if (u is String && u.isNotEmpty) {
            _keptExistingImageUrls.add(u);
          }
        }
      }
    }
    _cityController.addListener(_onCityTextChanged);
  }

  void _onCityTextChanged() {
    if (_suppressCityListener) {
      return;
    }
    _cityDebounce?.cancel();
    _cityDebounce = Timer(const Duration(milliseconds: 400), _fetchSuggestions);
  }

  Future<void> _fetchSuggestions() async {
    if (!mounted) {
      return;
    }
    final text = _cityController.text.trim();
    if (text.length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    try {
      final list = await GeocodingService.searchCities(text);
      if (!mounted) {
        return;
      }
      setState(() => _suggestions = list);
    } catch (_) {
      if (mounted) {
        setState(() => _suggestions = []);
      }
    }
  }

  @override
  void dispose() {
    _cityDebounce?.cancel();
    _cityController.removeListener(_onCityTextChanged);
    _bioController.dispose();
    _cityController.dispose();
    _interestController.dispose();
    _cityFocus.dispose();
    super.dispose();
  }

  int get _totalPhotoCount => _keptExistingImageUrls.length + _newImages.length;

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final List<XFile> picked = [];
    if (kIsWeb) {
      final one = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (one != null) {
        picked.add(one);
      }
    } else {
      picked.addAll(await picker.pickMultiImage(imageQuality: 85));
    }
    if (!mounted || picked.isEmpty) {
      return;
    }
    setState(() {
      for (final f in picked) {
        if (_totalPhotoCount >= _maxProfilePhotos) {
          break;
        }
        _newImages.add(f);
      }
    });
  }

  void _removeNewImage(int index) {
    setState(() => _newImages.removeAt(index));
  }

  void _removeExistingUrl(int index) {
    setState(() => _keptExistingImageUrls.removeAt(index));
  }

  void _selectCity(GeocodeSuggestion s) {
    _cityDebounce?.cancel();
    _suppressCityListener = true;
    _cityController.text = s.label;
    _suppressCityListener = false;
    if (!mounted) {
      return;
    }
    setState(() {
      _latitude = s.latitude;
      _longitude = s.longitude;
      _suggestions = [];
    });
    _cityFocus.unfocus();
  }

  void _dismissCitySuggestions() {
    _cityDebounce?.cancel();
    if (!mounted) {
      return;
    }
    setState(() => _suggestions = []);
  }

  void _addInterest() {
    final v = _interestController.text.trim();
    if (v.isEmpty) {
      return;
    }
    if (_interests.contains(v)) {
      _interestController.clear();
      return;
    }
    setState(() {
      _interests.add(v);
      _interestController.clear();
    });
  }

  String _contentTypeFor(XFile f) {
    final n = f.name.toLowerCase();
    if (n.endsWith('.png')) {
      return 'image/png';
    }
    if (n.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  Future<List<String>> _uploadNewImages() async {
    final uid = widget.user.uid;
    final urls = <String>[];
    var index = 0;
    for (final file in _newImages) {
      final bytes = await file.readAsBytes();
      final name = '${DateTime.now().microsecondsSinceEpoch}_$index';
      final ref = FirebaseStorage.instance.ref(
        'users/$uid/profile_images/$name.jpg',
      );
      await ref.putData(
        bytes,
        SettableMetadata(contentType: _contentTypeFor(file)),
      );
      urls.add(await ref.getDownloadURL());
      index++;
    }
    return urls;
  }

  Future<void> _save() async {
    setState(() {
      _errorMessage = null;
    });
    if (_totalPhotoCount < 1) {
      setState(() => _errorMessage = 'Add at least one profile photo.');
      return;
    }
    final city = _cityController.text.trim();
    if (city.isEmpty || _latitude == null || _longitude == null) {
      setState(
        () => _errorMessage = 'Choose your city from the suggestions list so we can save your location.',
      );
      return;
    }
    final bio = _bioController.text.trim();
    if (bio.isEmpty) {
      setState(() => _errorMessage = 'Please write a short bio.');
      return;
    }
    if (_interests.isEmpty) {
      setState(() => _errorMessage = 'Add at least one interest.');
      return;
    }

    setState(() => _saving = true);
    try {
      final uploaded = await _uploadNewImages();
      final allUrls = [..._keptExistingImageUrls, ...uploaded];
      await UserFirestore.saveOnboardingProfile(
        uid: widget.user.uid,
        profileImageUrls: allUrls,
        city: city,
        latitude: _latitude!,
        longitude: _longitude!,
        bio: bio,
        interests: List<String>.from(_interests),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not save profile: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your profile'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: _saving ? null : () => FirebaseAuth.instance.signOut(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Tell us about you',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Photos are stored in Firebase Storage; the rest is saved to your user document.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Text('Profile photos', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Up to $_maxProfilePhotos images · at least 1 required',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _keptExistingImageUrls.length; i++)
                  _PhotoThumb(
                    imageUrl: _keptExistingImageUrls[i],
                    onRemove: () => _removeExistingUrl(i),
                  ),
                for (var i = 0; i < _newImages.length; i++)
                  _PhotoThumb(
                    xFile: _newImages[i],
                    onRemove: () => _removeNewImage(i),
                  ),
                if (_totalPhotoCount < _maxProfilePhotos)
                  InkWell(
                    onTap: _saving ? null : _pickImages,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        border: Border.all(color: theme.colorScheme.outline),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.add_photo_alternate_outlined,
                        color: theme.colorScheme.primary,
                        size: 36,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            Text('City', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TapRegion(
              onTapOutside: (_) => _dismissCitySuggestions(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _cityController,
                    focusNode: _cityFocus,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Start typing your city',
                      border: OutlineInputBorder(),
                      hintText: 'e.g. Seattle',
                    ),
                    onChanged: (_) {
                      setState(() {
                        _latitude = null;
                        _longitude = null;
                      });
                    },
                  ),
                  if (_suggestions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Material(
                      elevation: 2,
                      borderRadius: BorderRadius.circular(8),
                      clipBehavior: Clip.antiAlias,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          physics: const ClampingScrollPhysics(),
                          itemCount: _suggestions.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final s = _suggestions[i];
                            return ListTile(
                              dense: true,
                              title: Text(s.label),
                              onTap: () => _selectCity(s),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Geocoding data from Open-Meteo (free, no API key).',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Text('Bio', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _bioController,
              maxLines: 4,
              maxLength: 500,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'A few sentences about you…',
              ),
            ),
            const SizedBox(height: 8),
            Text('Interests', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _interestController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Add an interest',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addInterest(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _saving ? null : _addInterest,
                  child: const Text('Add'),
                ),
              ],
            ),
            if (_interests.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _interests.length; i++)
                    InputChip(
                      label: Text(_interests[i]),
                      onDeleted: _saving
                          ? null
                          : () {
                              setState(() => _interests.removeAt(i));
                            },
                    ),
                ],
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 20),
              Text(
                _errorMessage!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save and continue'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({
    this.imageUrl,
    this.xFile,
    required this.onRemove,
  }) : assert(imageUrl != null || xFile != null);

  final String? imageUrl;
  final XFile? xFile;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    Widget imageChild;
    if (imageUrl != null) {
      imageChild = FirebaseProfileImage(url: imageUrl!);
    } else {
      imageChild = FutureBuilder<Uint8List>(
        future: xFile!.readAsBytes(),
        builder: (context, snap) {
          if (snap.hasError) {
            return const ColoredBox(
              color: Colors.black12,
              child: Icon(Icons.broken_image_outlined),
            );
          }
          if (!snap.hasData) {
            return const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          return Image.memory(snap.data!, fit: BoxFit.cover);
        },
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 88,
            height: 88,
            child: imageChild,
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: Material(
            color: Colors.black87,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
