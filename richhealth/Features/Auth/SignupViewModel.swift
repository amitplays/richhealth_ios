import Foundation
import Observation

@Observable @MainActor final class SignupViewModel {

    // ─── Step 0: Account ─────────────────────────────────────────────────────
    var name = ""
    var email = ""
    var phoneNumber = ""
    var password = ""
    var confirmPassword = ""

    // ─── Step 1: Personal ────────────────────────────────────────────────────
    var gender = ""
    var dateOfBirth: Date = Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now
    var location = ""

    // ─── Step 2: Physical ────────────────────────────────────────────────────
    var heightCm: Double = 170
    var weightKg: Double = 70
    var bloodType = ""              // optional — "A+" | "A-" | ... | ""

    // ─── Step 3: Goals & Diet ────────────────────────────────────────────────
    var primaryGoal = "Improve Fitness"
    var activityLevel = 3           // 1–5 matching OnboardingActivity.java configs
    var dietType = "No Preference"

    // ─── Step 4: Lifestyle & Health ──────────────────────────────────────────
    var sleepHours: Double = 7
    var smokingStatus = "never"     // "never"|"ex"|"social"|"occasional"|"regular"
    var alcoholConsumption = "None" // "None"|"Rarely"|"Special Occasions"|"Socially"|"Regularly"|"Frequently"
    var caffeineHabit = "none"      // "none"|"tea"|"coffee"|"both"|"energy_drinks"
    var medicalConditions = ""      // comma-separated, split before submit
    var allergies = ""              // comma-separated, split before submit

    // ─── Navigation ──────────────────────────────────────────────────────────
    var step = 0
    static let totalSteps = 5

    // ─── State ───────────────────────────────────────────────────────────────
    var isLoading = false
    var errorMessage: String?
    var isAccountCreated = false

    // ─── OTP ─────────────────────────────────────────────────────────────────
    var otpCode = ""
    var isOTPLoading = false
    var otpMessage: String?

    // ─── Options (mirrors Android OnboardingActivity.java configs) ────────────
    let genderOptions   = ["Male", "Female", "Other"]
    let activityOptions = ["Mostly Sitting", "Light Activity", "Moderately Active", "Very Active", "Athlete"]
    let goalOptions     = ["Improve Fitness", "Weight Loss", "Muscle Gain",
                           "Manage a Health Condition", "Boost Energy",
                           "Improve Sleep", "Eat Healthier", "Improve Mental Health"]
    let dietOptions     = ["No Preference", "Regular", "Vegetarian", "Vegan",
                           "Keto", "Mediterranean", "Gluten-Free", "Other"]
    let bloodTypeOptions = ["", "A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-", "Don't know"]

    // ─── Validation ──────────────────────────────────────────────────────────

    var validationError: String? {
        switch step {
        case 0:
            if name.isEmpty               { return "Please enter your name." }
            if email.isEmpty              { return "Please enter your email." }
            if password.count < 6         { return "Password must be at least 6 characters." }
            if password != confirmPassword { return "Passwords do not match." }
        case 1:
            if gender.isEmpty             { return "Please select your gender." }
        case 2:
            if heightCm <= 0              { return "Please enter a valid height." }
            if weightKg <= 0              { return "Please enter a valid weight." }
        default: break
        }
        return nil
    }

    // ─── Navigation ──────────────────────────────────────────────────────────

    func next() {
        errorMessage = validationError
        if errorMessage == nil, step < Self.totalSteps - 1 { step += 1 }
    }

    func back() {
        errorMessage = nil
        if step > 0 { step -= 1 }
    }

    // ─── Submit ───────────────────────────────────────────────────────────────
    // POST /api/auth/signup — sends all collected fields including optional ones.

    func submit(auth: AuthManager) async {
        if let err = validationError { errorMessage = err; return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        func csv(_ s: String) -> [String]? {
            let arr = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return arr.isEmpty ? nil : arr
        }

        let request = SignupRequest(
            email: email,
            password: password,
            confirmPassword: confirmPassword,
            name: name,
            gender: gender,
            dateOfBirth: formatter.string(from: dateOfBirth),
            height: heightCm,
            weight: weightKg,
            activityLevel: activityLevel,
            dietType: dietType,
            phoneNumber: phoneNumber.isEmpty ? nil : phoneNumber,
            location: location.isEmpty ? nil : location,
            primaryGoal: primaryGoal.isEmpty ? nil : primaryGoal,
            bloodType: bloodType.isEmpty ? nil : bloodType,
            sleepHours: sleepHours > 0 ? sleepHours : nil,
            smokingStatus: smokingStatus == "never" ? nil : smokingStatus,
            alcoholConsumption: alcoholConsumption == "None" ? nil : alcoholConsumption,
            caffeineHabit: caffeineHabit == "none" ? nil : caffeineHabit,
            medicalConditions: csv(medicalConditions),
            allergies: csv(allergies)
        )

        do {
            try await auth.signup(request)
            isAccountCreated = true
            await sendOTP(auth: auth)
        } catch let err as APIError {
            errorMessage = err.userMessage
        } catch {
            errorMessage = "Signup failed. Please try again."
        }
    }

    // ─── OTP ─────────────────────────────────────────────────────────────────

    func sendOTP(auth: AuthManager) async {
        isOTPLoading = true
        otpMessage = nil
        defer { isOTPLoading = false }
        do {
            let response = try await auth.sendOTP(email: email)
            if response.alreadyVerified == true {
                await auth.activateSession()
            } else {
                otpMessage = response.emailSent == true
                    ? "Code sent to \(email)."
                    : "Couldn't email the code — enter it manually or skip."
            }
        } catch let err as APIError {
            otpMessage = err.userMessage
        } catch {
            otpMessage = "Could not send code. You can skip verification for now."
        }
    }

    func verifyOTP(auth: AuthManager) async {
        guard !otpCode.isEmpty else { otpMessage = "Please enter the 6-digit code."; return }
        isOTPLoading = true
        otpMessage = nil
        defer { isOTPLoading = false }
        do {
            let response = try await auth.verifyOTP(email: email, otp: otpCode)
            if response.verified == true {
                await auth.activateSession()
            } else {
                otpMessage = response.message ?? "Incorrect code. Please try again."
            }
        } catch let err as APIError {
            otpMessage = err.userMessage
        } catch {
            otpMessage = "Verification failed. Please try again."
        }
    }

    func skipOTP(auth: AuthManager) async {
        await auth.activateSession()
    }
}
