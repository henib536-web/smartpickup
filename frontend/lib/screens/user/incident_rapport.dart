import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../../env.dart';

/// Page de signalement d'incident
/// Équivalent de ReportIncident.tsx en React
class ReportIncidentPage extends StatefulWidget {
  final String? rideId;
  const ReportIncidentPage({Key? key, this.rideId}) : super(key: key);

  @override
  State<ReportIncidentPage> createState() => _ReportIncidentPageState();
}

class _ReportIncidentPageState extends State<ReportIncidentPage>
    with SingleTickerProviderStateMixin {
  // Types d'incidents
  String? _selectedIncidentType;
  int _severityLevel = 3;
  String _description = '';
  String? _selectedRideId;
  final List<File> _photos = [];
  bool _isSubmitting = false;
  bool _isSubmitted = false;
  bool _isRideDropdownOpen = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  final ImagePicker _picker = ImagePicker();
  final TextEditingController _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedRideId = widget.rideId;
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    )..forward();

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // Données de courses terminées
  final List<Map<String, dynamic>> _completedRides = [
    {
      'id': 'R-2024',
      'date': 'Apr 5, 2026 - 08:00 AM',
      'pickup': '123 Main Street, Downtown',
      'dropoff': '456 School Road, Oakville',
      'driver': 'Michael Rodriguez',
      'fare': '\$18.50',
      'status': 'complete',
    },
    {
      'id': 'R-2023',
      'date': 'Apr 4, 2026 - 02:30 PM',
      'pickup': '789 Park Avenue',
      'dropoff': '321 Oak Street',
      'driver': 'Sarah Johnson',
      'fare': '\$24.00',
      'status': 'complete',
    },
    {
      'id': 'R-2022',
      'date': 'Apr 3, 2026 - 09:15 AM',
      'pickup': '555 Business Center',
      'dropoff': '999 Shopping Mall',
      'driver': 'David Chen',
      'fare': '\$31.75',
      'status': 'complete',
    },
    {
      'id': 'R-2021',
      'date': 'Apr 2, 2026 - 06:45 PM',
      'pickup': '111 Restaurant Row',
      'dropoff': '222 Residential Ave',
      'driver': 'Emma Williams',
      'fare': '\$15.25',
      'status': 'complete',
    },
    {
      'id': 'R-2020',
      'date': 'Apr 1, 2026 - 11:00 AM',
      'pickup': '777 Airport Terminal',
      'dropoff': '888 Hotel Plaza',
      'driver': 'James Brown',
      'fare': '\$42.50',
      'status': 'complete',
    },
  ];

  // Types d'incidents
  final List<Map<String, dynamic>> _incidentTypes = [
    {
      'id': 'lost_item',
      'label': 'Objet oublié',
      'description': 'Signaler un objet oublié dans le véhicule',
      'icon': Icons.shopping_bag,
      'colors': [Colors.blue, Colors.cyan],
      'bgColor': Colors.blue,
      'borderColor': Colors.blue,
    },
    {
      'id': 'accident',
      'label': 'Accident',
      'description': 'Signaler un accident survenu durant la course',
      'icon': Icons.warning,
      'colors': [Colors.red, Colors.orange],
      'bgColor': Colors.red,
      'borderColor': Colors.red,
    },
    {
      'id': 'inappropriate_behavior',
      'label': 'Comportement inapproprié',
      'description': 'Signaler un comportement inapproprié du chauffeur',
      'icon': Icons.person_off,
      'colors': [Colors.purple, Colors.pink],
      'bgColor': Colors.purple,
      'borderColor': Colors.purple,
    },
    {
      'id': 'payment_issue',
      'label': 'Problème de paiement',
      'description': 'Signaler un problème lié au paiement',
      'icon': Icons.attach_money,
      'colors': [Colors.green, Colors.teal],
      'bgColor': Colors.green,
      'borderColor': Colors.green,
    },
  ];

  // Niveaux de gravité
  final List<Map<String, dynamic>> _severityLevels = [
    {
      'value': 1,
      'label': 'Mineur',
      'color': const Color(0xFF22c55e),
      'description': 'Problème non urgent'
    },
    {
      'value': 2,
      'label': 'Faible',
      'color': const Color(0xFF84cc16),
      'description': 'Nécessite attention'
    },
    {
      'value': 3,
      'label': 'Modéré',
      'color': const Color(0xFFFFCC00),
      'description': 'À traiter rapidement'
    },
    {
      'value': 4,
      'label': 'Élevé',
      'color': const Color(0xFFf97316),
      'description': 'Nécessite action rapide'
    },
    {
      'value': 5,
      'label': 'Critique',
      'color': const Color(0xFFef4444),
      'description': 'Urgence immédiate'
    },
  ];

  Future<void> _pickImages() async {
    if (_photos.length >= 5) {
      _showSnackBar('Maximum 5 photos autorisées');
      return;
    }

    final List<XFile> images = await _picker.pickMultiImage();
    
    if (images.isNotEmpty) {
      setState(() {
        for (var image in images) {
          if (_photos.length < 5) {
            _photos.add(File(image.path));
          }
        }
      });
    }
  }

  void _removePhoto(int index) {
    setState(() {
      _photos.removeAt(index);
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF1a1a1a),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _submitForm() async {
    // Validation
    if (_selectedIncidentType == null) {
      _showSnackBar('Veuillez sélectionner un type d\'incident');
      return;
    }

    if (_description.trim().isEmpty) {
      _showSnackBar('Veuillez décrire l\'incident');
      return;
    }

    if (_description.trim().length < 20) {
      _showSnackBar('La description doit contenir au moins 20 caractères');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final res = await http.post(
        Uri.parse('${Env.baseUrl}/rides/$_selectedRideId/report'),
        headers: {
          ...Env.defaultHeaders,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'report_type': _selectedIncidentType,
          'severity_level': _severityLevel,
          'description': _description,
        }),
      );

      if (res.statusCode == 200) {
        setState(() {
          _isSubmitted = true;
        });
        _showSnackBar('Incident signalé avec succès');
      } else {
        _showSnackBar('Erreur lors du signalement : ${res.body}');
      }
    } catch (e) {
      _showSnackBar('Erreur de connexion');
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }

    _showSnackBar('Incident signalé avec succès');

    // Réinitialiser après 3 secondes
    await Future.delayed(const Duration(seconds: 3));

    setState(() {
      _isSubmitted = false;
      _selectedIncidentType = null;
      _severityLevel = 3;
      _description = '';
      _descriptionController.clear();
      _selectedRideId = null;
      _photos.clear();
    });
  }

  Map<String, dynamic>? get _currentSeverity => _severityLevels.firstWhere(
        (level) => level['value'] == _severityLevel,
        orElse: () => _severityLevels[2],
      );

  Map<String, dynamic>? get _selectedRide => _completedRides.firstWhere(
        (ride) => ride['id'] == _selectedRideId,
        orElse: () => {},
      );

  @override
  Widget build(BuildContext context) {
    if (_isSubmitted) {
      return _buildSuccessScreen();
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0a),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0a0a0a),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Signaler un Incident',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.report_problem, color: Color(0xFFFFCC00), size: 40),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Signaler un Incident',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Décrivez le problème rencontré durant votre course. Notre équipe traitera votre signalement rapidement.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFFa0a0a0),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Type d'incident
            _buildIncidentTypeSection(),
            const SizedBox(height: 24),

            // Niveau de gravité
            _buildSeveritySection(),
            const SizedBox(height: 24),

            // Sélecteur de course
            _buildRideSelector(),
            const SizedBox(height: 24),

            // Description
            _buildDescriptionSection(),
            const SizedBox(height: 24),

            // Photos
            _buildPhotoSection(),
            const SizedBox(height: 24),

            // Boutons
            _buildActionButtons(),
            const SizedBox(height: 24),

            // Avertissement
            _buildWarning(),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0a),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            padding: const EdgeInsets.all(48),
            decoration: BoxDecoration(
              color: const Color(0xFF1a1a1a),
              border: Border.all(color: const Color(0xFF333333)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Colors.green, Colors.teal],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Incident signalé avec succès !',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Votre rapport a été enregistré et sera traité dans les plus brefs délais.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFFa0a0a0),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Numéro de référence: INC-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
                  style: const TextStyle(
                    color: Color(0xFFa0a0a0),
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Retour au formulaire dans quelques secondes...',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFFa0a0a0),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIncidentTypeSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a1a),
        border: Border.all(color: const Color(0xFF333333)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.description, color: Color(0xFFFFCC00), size: 24),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Type d\'incident',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Sélectionnez le type d\'incident que vous souhaitez signaler',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFFa0a0a0),
            ),
          ),
          const SizedBox(height: 24),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: MediaQuery.of(context).size.width < 400 ? 0.85 : 1.1,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _incidentTypes.length,
            itemBuilder: (context, index) {
              final type = _incidentTypes[index];
              final isSelected = _selectedIncidentType == type['id'];

              return InkWell(
                onTap: () {
                  setState(() {
                    _selectedIncidentType = type['id'];
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0f0f0f),
                    border: Border.all(
                      color: isSelected
                          ? type['borderColor']
                          : const Color(0xFF333333),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: type['colors'],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            type['icon'],
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          type['label'],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        type['description'],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFFa0a0a0),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (isSelected)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Icon(
                            Icons.check_circle,
                            color: Color(0xFFFFCC00),
                            size: 24,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSeveritySection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a1a),
        border: Border.all(color: const Color(0xFF333333)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.warning_amber, color: Color(0xFFFFCC00), size: 24),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Niveau de gravité',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Indiquez la gravité de l\'incident (1 = Mineur, 5 = Critique)',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFFa0a0a0),
            ),
          ),
          const SizedBox(height: 24),
          
          // Indicateur visuel
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0f0f0f),
              border: Border.all(color: _currentSeverity!['color'], width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Niveau $_severityLevel',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: _currentSeverity!['color'],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _currentSeverity!['label'],
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _currentSeverity!['description'],
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFFa0a0a0),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: Container(
                    width: MediaQuery.of(context).size.width < 400 ? 60 : 80,
                    height: MediaQuery.of(context).size.width < 400 ? 60 : 80,
                    decoration: BoxDecoration(
                      color: _currentSeverity!['color'],
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$_severityLevel',
                        style: TextStyle(
                          fontSize: MediaQuery.of(context).size.width < 400 ? 24 : 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Slider
          Slider(
            value: _severityLevel.toDouble(),
            min: 1,
            max: 5,
            divisions: 4,
            activeColor: _currentSeverity!['color'],
            inactiveColor: const Color(0xFF333333),
            onChanged: (value) {
              setState(() {
                _severityLevel = value.round();
              });
            },
          ),
          
          // Labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(5, (index) {
              final level = index + 1;
              return Text(
                '$level',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: _severityLevel == level ? FontWeight.bold : FontWeight.normal,
                  color: _severityLevel == level ? Colors.white : const Color(0xFFa0a0a0),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildRideSelector() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a1a),
        border: Border.all(color: const Color(0xFF333333)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Course concernée (optionnel)',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Sélectionnez la course pour laquelle vous souhaitez signaler un incident',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFFa0a0a0),
            ),
          ),
          const SizedBox(height: 16),
          
          // Dropdown button
          InkWell(
            onTap: () {
              setState(() {
                _isRideDropdownOpen = !_isRideDropdownOpen;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0f0f0f),
                border: Border.all(color: const Color(0xFF333333)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _selectedRideId != null
                          ? '$_selectedRideId - ${_selectedRide!['date']}'
                          : 'Sélectionnez une course',
                      style: TextStyle(
                        color: _selectedRideId != null
                            ? Colors.white
                            : const Color(0xFF555555),
                      ),
                    ),
                  ),
                  Icon(
                    _isRideDropdownOpen
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ),
          
          // Dropdown menu
          if (_isRideDropdownOpen) ...[
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 400),
              decoration: BoxDecoration(
                color: const Color(0xFF0f0f0f),
                border: Border.all(color: const Color(0xFF333333)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  // Option "Aucune"
                  InkWell(
                    onTap: () {
                      setState(() {
                        _selectedRideId = null;
                        _isRideDropdownOpen = false;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Color(0xFF333333)),
                        ),
                      ),
                      child: const Text(
                        'Aucune course sélectionnée',
                        style: TextStyle(
                          color: Color(0xFFa0a0a0),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ),
                  
                  // Liste des courses
                  ..._completedRides.map((ride) {
                    final isSelected = _selectedRideId == ride['id'];
                    return InkWell(
                      onTap: () {
                        setState(() {
                          _selectedRideId = ride['id'];
                          _isRideDropdownOpen = false;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFFFCC00).withOpacity(0.1)
                              : Colors.transparent,
                          border: const Border(
                            bottom: BorderSide(color: Color(0xFF333333)),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  ride['id'],
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFFFCC00),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.calendar_today,
                                          size: 16, color: Color(0xFFa0a0a0)),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          ride['date'],
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFFa0a0a0),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(Icons.location_on,
                                    size: 16, color: Colors.green),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    ride['pickup'],
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFFa0a0a0),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.location_on,
                                    size: 16, color: Colors.red),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    ride['dropoff'],
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFFa0a0a0),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.only(top: 8),
                              decoration: const BoxDecoration(
                                border: Border(
                                  top: BorderSide(color: Color(0xFF333333)),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Chauffeur: ${ride['driver']}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFFa0a0a0),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    ride['fare'],
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFFFCC00),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ],
          
          // Aperçu de la course sélectionnée
          if (_selectedRideId != null && !_isRideDropdownOpen) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0f0f0f),
                border: Border.all(
                  color: const Color(0xFFFFCC00).withOpacity(0.3),
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Course sélectionnée',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFa0a0a0),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _selectedRideId!,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFFCC00),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        onPressed: () {
                          setState(() {
                            _selectedRideId = null;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Date',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFa0a0a0),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _selectedRide?['date'] ?? 'N/A',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Chauffeur',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFa0a0a0),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _selectedRide?['driver'] ?? 'Inconnu',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Tarif',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFa0a0a0),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _selectedRide?['fare'] ?? 'N/A',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFFCC00),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Statut',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFa0a0a0),
                              ),
                            ),
                            SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.check_circle,
                                    size: 16, color: Colors.green),
                                SizedBox(width: 4),
                                Text(
                                  'Terminée',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDescriptionSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a1a),
        border: Border.all(color: const Color(0xFF333333)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Description détaillée *',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Décrivez l\'incident de manière détaillée (minimum 20 caractères)',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFFa0a0a0),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descriptionController,
            maxLines: 6,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText:
                  'Décrivez en détail ce qui s\'est passé, les circonstances, les personnes impliquées, etc.',
              hintStyle: const TextStyle(color: Color(0xFF555555)),
              filled: true,
              fillColor: const Color(0xFF0f0f0f),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF333333)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF333333)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFFFCC00)),
              ),
            ),
            onChanged: (value) {
              setState(() {
                _description = value;
              });
            },
          ),
          const SizedBox(height: 8),
          Text(
            '${_description.length} caractères${_description.length < 20 ? ' (minimum 20 requis)' : ''}',
            style: TextStyle(
              fontSize: 12,
              color: _description.length < 20
                  ? Colors.red
                  : _description.length < 50
                      ? Colors.yellow
                      : Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a1a),
        border: Border.all(color: const Color(0xFF333333)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.camera_alt, color: Color(0xFFFFCC00), size: 24),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Preuves photographiques (optionnel)',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Ajoutez jusqu\'à 5 photos pour documenter l\'incident',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFFa0a0a0),
            ),
          ),
          const SizedBox(height: 16),
          
          // Zone de upload
          if (_photos.length < 5)
            InkWell(
              onTap: _pickImages,
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: const Color(0xFF0f0f0f),
                  border: Border.all(
                    color: const Color(0xFF333333),
                    width: 2,
                    style: BorderStyle.solid,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFCC00), Color(0xFFff9900)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.upload,
                        size: 32,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Cliquez pour télécharger des photos',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'PNG, JPG jusqu\'à 5MB (${5 - _photos.length} restantes)',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFa0a0a0),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          
          // Grille de photos
          if (_photos.isNotEmpty) ...[
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _photos.length,
              itemBuilder: (context, index) {
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        _photos[index],
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: InkWell(
                        onTap: () => _removePhoto(index),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    bool isSmallScreen = MediaQuery.of(context).size.width < 350;
    
    return isSmallScreen 
      ? Column(
          children: [
            _buildSubmitButtonContent(),
            const SizedBox(height: 12),
            _buildResetButtonContent(),
          ],
        )
      : Row(
          children: [
            Expanded(flex: 2, child: _buildSubmitButtonContent()),
            const SizedBox(width: 12),
            Expanded(child: _buildResetButtonContent()),
          ],
        );
  }

  Widget _buildSubmitButtonContent() {
    return ElevatedButton(
      onPressed: _isSubmitting ? null : _submitForm,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFFFCC00),
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 16),
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 0,
      ),
      child: _isSubmitting
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
              ),
            )
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.send, size: 24),
                  SizedBox(width: 12),
                  Text(
                    'Envoyer le rapport',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildResetButtonContent() {
    return OutlinedButton(
      onPressed: () {
        setState(() {
          _selectedIncidentType = null;
          _severityLevel = 3;
          _description = '';
          _descriptionController.clear();
          _selectedRideId = null;
          _photos.clear();
        });
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFF333333), width: 2),
        padding: const EdgeInsets.symmetric(vertical: 16),
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: const Text(
        'Réinitialiser',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildWarning() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.yellow.withOpacity(0.1),
        border: Border.all(
          color: Colors.yellow.withOpacity(0.3),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(
            Icons.warning,
            color: Colors.yellow,
            size: 20,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Important',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.yellow,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Les fausses déclarations peuvent entraîner la suspension de votre compte. Assurez-vous que toutes les informations fournies sont exactes et véridiques.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.yellow,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
