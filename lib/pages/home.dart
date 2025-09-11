// lib/pages/home.dart
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

class HomePageContent extends StatefulWidget {
  const HomePageContent({super.key});

  @override
  State<HomePageContent> createState() => _HomePageContentState();
}

class _HomePageContentState extends State<HomePageContent> {
  // App theme colors to match government portal
  static const Color _primaryBlue = Color(0xFF1E3A8A);
  static const Color _lightGray = Color(0xFFF8FAFC);
  static const Color _borderGray = Color(0xFFE2E8F0);
  static const Color _textGray = Color(0xFF64748B);

  // Controllers & state for the Home UI
  final TextEditingController _dlController = TextEditingController();
  final TextEditingController _rcController = TextEditingController();

  String? _dlImageName;
  String? _rcImageName;
  String? _driverImageName;

  // Loading states for future API integration
  bool _isVerifying = false;

  @override
  void dispose() {
    _dlController.dispose();
    _rcController.dispose();
    super.dispose();
  }

  // File picker methods (now inside home.dart)
  Future<void> _pickDlImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _dlImageName = result.files.single.name;
        // TODO: Integrate with OCR API when ready
        _dlController.text = ''; // Will be populated by OCR
      });
    }
  }

  Future<void> _pickRcImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _rcImageName = result.files.single.name;
        // TODO: Integrate with RC OCR API when ready
        _rcController.text = ''; // Will be populated by OCR
      });
    }
  }

  Future<void> _pickDriverImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _driverImageName = result.files.single.name;
      });
    }
  }

  Future<void> _handleVerification() async {
    // Basic validation
    if (_dlController.text.isEmpty && _dlImageName == null) {
      _showErrorSnackBar('Please provide driving license information');
      return;
    }

    if (_rcController.text.isEmpty && _rcImageName == null) {
      _showErrorSnackBar('Please provide vehicle registration information');
      return;
    }

    setState(() {
      _isVerifying = true;
    });

    // Simulate API call delay
    await Future.delayed(const Duration(seconds: 2));

    setState(() {
      _isVerifying = false;
    });

    // TODO: Implement actual API calls to your AI models
    _showInfoSnackBar('Verification completed! (API integration pending)');
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showInfoSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _lightGray,
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Header section with government branding
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    'Driving License and Vehicle Registration Certificate Verification Portal',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _primaryBlue,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Main form container
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Driving License Section
                  _buildSectionHeader(
                    icon: Icons.credit_card,
                    title: 'Upload Driving License',
                    subtitle: 'Upload your driving license document',
                  ),
                  const SizedBox(height: 16),

                  _buildFileUploadCard(
                    label: 'Choose Driving License File',
                    fileName: _dlImageName,
                    onTap: _pickDlImage,
                    icon: Icons.upload_file,
                  ),

                  const SizedBox(height: 12),

                  _buildTextInput(
                    controller: _dlController,
                    label: 'Driving License Number',
                    hint: 'Select image or enter manually',
                    prefixIcon: Icons.confirmation_number,
                  ),

                  const SizedBox(height: 24),

                  // Vehicle Registration Section
                  _buildSectionHeader(
                    icon: Icons.directions_car,
                    title: 'Upload Vehicle Registration Number (Number Plate Number)',
                    subtitle: 'Upload your vehicle registration certificate',
                  ),
                  const SizedBox(height: 16),

                  _buildFileUploadCard(
                    label: 'Choose Vehicle Registration File',
                    fileName: _rcImageName,
                    onTap: _pickRcImage,
                    icon: Icons.upload_file,
                  ),

                  const SizedBox(height: 12),

                  _buildTextInput(
                    controller: _rcController,
                    label: 'Vehicle Number',
                    hint: 'Select image or enter manually',
                    prefixIcon: Icons.directions_car,
                  ),

                  const SizedBox(height: 24),

                  // Driver Image Section
                  _buildSectionHeader(
                    icon: Icons.person,
                    title: 'Upload Driver Image',
                    subtitle: 'Upload a clear photo of the driver',
                  ),
                  const SizedBox(height: 16),

                  _buildFileUploadCard(
                    label: 'Choose Driver Image File',
                    fileName: _driverImageName,
                    onTap: _pickDriverImage,
                    icon: Icons.person_add_alt_1,
                  ),

                  const SizedBox(height: 32),

                  // Verify Information Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isVerifying ? null : _handleVerification,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryBlue,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        disabledBackgroundColor: Colors.grey.shade400,
                      ),
                      child: _isVerifying
                          ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          SizedBox(width: 12),
                          Text('Verifying...', style: TextStyle(fontSize: 16)),
                        ],
                      )
                          : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.verified_user, size: 20),
                          SizedBox(width: 8),
                          Text('Verify Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Info note
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade600, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'AI-powered verification will extract information from uploaded documents automatically.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _primaryBlue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: _primaryBlue, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: _textGray,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFileUploadCard({
    required String label,
    required String? fileName,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: _borderGray),
          borderRadius: BorderRadius.circular(8),
          color: fileName != null ? Colors.green.shade50 : _lightGray,
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color: fileName != null ? Colors.green.shade600 : _textGray,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    fileName ?? label,
                    style: TextStyle(
                      fontSize: 14,
                      color: fileName != null ? Colors.green.shade700 : _textGray,
                      fontWeight: fileName != null ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                ),
                if (fileName != null) Icon(Icons.check_circle, color: Colors.green.shade600, size: 18),
              ],
            ),
            if (fileName == null) ...[
              const SizedBox(height: 8),
              Text(
                'No file chosen',
                style: TextStyle(fontSize: 12, color: _textGray),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTextInput({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData prefixIcon,
  }) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(prefixIcon, size: 18),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _borderGray),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _borderGray),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _primaryBlue, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}