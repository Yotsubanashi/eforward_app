import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dashboard.dart'; // 👈 add this

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _obscurePassword = true;
  bool _rememberMe = false;
  final TextEditingController _emailController = TextEditingController();    // 👈 add
  final TextEditingController _passwordController = TextEditingController(); // 👈 add

   @override
  void initState() {
    super.initState();
    _loadRememberedEmail();
  }

  // 👇 2. ADD these 2 methods HERE
  void _loadRememberedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('remember_me') ?? false) {
      _emailController.text = prefs.getString('saved_email') ?? '';
      setState(() => _rememberMe = true);
    }
  }

  void _saveRememberMe(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remember_me', _rememberMe);
    _rememberMe
        ? await prefs.setString('saved_email', email)
        : await prefs.remove('saved_email');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Logo + Brand
              Row(
                children: [
                  Icon(Icons.shield_outlined, color: Color(0xFFCC0000), size: 20),
                  SizedBox(width: 6),
                  Text("E-FORWARD",
                    style: TextStyle(
                      color: Color(0xFFCC0000),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    )),
                ],
              ),
              SizedBox(height: 102),

              // Title
              Center(
                child: Column(
                  children: [
                    Text("SECURE ACCESS",
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      )),
                    SizedBox(height: 8),
                    Text(
                      "INSTITUTIONAL-GRADE APPROVAL WORKFLOW\nAND DOCUMENT GOVERNANCE.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 40),

              // Email Field
              Text("EMAIL",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              SizedBox(height: 6),
              TextField(
                controller: _emailController, // 👈 add
                decoration: InputDecoration(
                  hintText: "ENTER EMAIL ADDRESS",
                  hintStyle: TextStyle(color: Colors.black26, fontSize: 12),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.black26),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFCC0000)),
                  ),
                ),
              ),
              SizedBox(height: 24),

              // Password Field
              Text("PASSWORD",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              SizedBox(height: 6),
              TextField(
                controller: _passwordController, // 👈 add
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  hintText: "ENTER PASSWORD",
                  hintStyle: TextStyle(color: Colors.black26, fontSize: 12),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: Colors.black38,
                      size: 20,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.black26),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFCC0000)),
                  ),
                ),
              ),
              SizedBox(height: 20),

          //Remember Me Checkbox      
              Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: _rememberMe,
                        onChanged: (val) => setState(() => _rememberMe = val ?? false),
                        activeColor: Color.fromARGB(255, 1, 0, 0), // or your theme color
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        side: BorderSide(color: Colors.black38, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      "Remember Me",
                      style: TextStyle(
                        color: const Color.fromARGB(133, 15, 1, 1),
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),

                SizedBox(height: 20),
              // Login Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    String email = _emailController.text.trim();
                    String password = _passwordController.text.trim();

                    if (email == "mark.almueda@ardentnetworks.com.ph" && password == "Mark001!") {
                      _saveRememberMe(email); 
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (context) => DashboardPage()),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Invalid email or password!"),
                          backgroundColor: Color(0xFFCC0000),
                        ),
                      );
                    }
                  }, // 👈 updated
                  icon: Icon(Icons.arrow_forward, color: Colors.white),
                  label: Text("LOGIN",
                    style: TextStyle(
                      color: Colors.white,
                      letterSpacing: 2,
                      fontWeight: FontWeight.bold,
                    )),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFFCC0000),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 24),

              // Forgot Password
              Center(
                child: TextButton(
                  onPressed: () {},
                  child: Text("FORGOT PASSWORD",
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 12,
                      letterSpacing: 1.5,
                    )),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}