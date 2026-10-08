package br.com.cortaaqui.auth;

import br.com.cortaaqui.common.Checks;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/auth")
public class AuthController {

    private final AuthService authService;
    private final Access access;

    public AuthController(AuthService authService, Access access) {
        this.authService = authService;
        this.access = access;
    }

    public record LoginRequest(String email, String password) {
    }

    @PostMapping("/login")
    public AuthService.Session login(@RequestBody LoginRequest req) {
        Checks.start()
                .text("email", req.email(), 3, 120, true)
                .text("password", req.password(), 1, 72, true)
                .orThrow();
        return authService.login(req.email(), req.password());
    }

    @GetMapping("/me")
    public AuthService.StaffUserView me() {
        return authService.me(access.principal().userId());
    }

    @PostMapping("/logout")
    public ResponseEntity<Void> logout() {
        authService.logout(access.principal());
        return ResponseEntity.noContent().build();
    }
}
