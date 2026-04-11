#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Atlas CMMS Özelleştirme Setup Scripti
# Kullanım : ./setup.sh <upstream-klasörü> [--no-docker]
# Örnek    : ./setup.sh ./atlas-main
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

TARGET="${1:-$(pwd)}"
TARGET="$(cd "$TARGET" && pwd)"
START_DOCKER=true
[[ "${2:-}" == "--no-docker" ]] && START_DOCKER=false

API="$TARGET/api"
FE="$TARGET/frontend"
CHANGELOG="$API/src/main/resources/db/changelog"
MASTER="$API/src/main/resources/db/master.xml"

# ── Kontroller ─────────────────────────────────────────────────────────────
if [[ ! -d "$API" ]]; then echo "HATA: $API bulunamadı. Doğru upstream klasörünü verin."; exit 1; fi
if [[ ! -d "$FE"  ]]; then echo "HATA: $FE bulunamadı.";  exit 1; fi
command -v python3 >/dev/null || { echo "HATA: python3 gerekli"; exit 1; }

ok()  { echo "  ✓ $*"; }
hdr() { echo ""; echo "▶ $*"; }

# ────────────────────────────────────────────────────────────────────────────
# Yardımcı: dosya yaz (dizini de oluştur)
# ────────────────────────────────────────────────────────────────────────────
wf() {   # wf <path> <content-variable>
    local p="$1"; local c="$2"
    mkdir -p "$(dirname "$p")"
    printf '%s' "$c" > "$p"
    ok "$p"
}

echo "══════════════════════════════════════════════════════════════"
echo "  Atlas CMMS Özelleştirme Setup"
echo "  Hedef : $TARGET"
echo "══════════════════════════════════════════════════════════════"

# ════════════════════════════════════════════════════════════════════════════
# BÖLÜM 1 – BACKEND: Yeni Java dosyaları
# ════════════════════════════════════════════════════════════════════════════
hdr "1/8  Backend – Yeni Java dosyaları"

# ── LicenseService ──────────────────────────────────────────────────────────
wf "$API/src/main/java/com/grash/service/LicenseService.java" \
'package com.grash.service;

import com.grash.dto.license.LicenseEntitlement;
import com.grash.dto.license.LicensingState;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
@Slf4j
public class LicenseService {

    public LicensingState getLicensingState() {
        return LicensingState.builder()
                .hasLicense(true)
                .valid(true)
                .build();
    }

    public boolean isSSOEnabled() {
        return true;
    }

    public boolean hasEntitlement(LicenseEntitlement entitlement) {
        return true;
    }
}
'

# ── PlanFeatures enum ────────────────────────────────────────────────────────
wf "$API/src/main/java/com/grash/model/enums/PlanFeatures.java" \
'package com.grash.model.enums;

public enum PlanFeatures {
    PREVENTIVE_MAINTENANCE,
    CHECKLIST,
    FILE,
    PURCHASE_ORDER,
    METER,
    REQUEST_CONFIGURATION,
    ADDITIONAL_TIME,
    ADDITIONAL_COST,
    ANALYTICS,
    REQUEST_PORTAL,
    SIGNATURE,
    ROLE,
    WORKFLOW,
    API_ACCESS,
    WEBHOOK,
    IMPORT_CSV
}
'

# ── CompanyFeatureOverride entity ────────────────────────────────────────────
wf "$API/src/main/java/com/grash/model/CompanyFeatureOverride.java" \
'package com.grash.model;

import com.grash.model.abstracts.Audit;
import com.grash.model.enums.PlanFeatures;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.persistence.*;

@Entity
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class CompanyFeatureOverride extends Audit {

    @Id
    @GeneratedValue(strategy = GenerationType.AUTO)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "company_id", nullable = false)
    private Company company;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 100)
    private PlanFeatures feature;

    @Column(nullable = false)
    private boolean enabled;
}
'

# ── Feature entity ───────────────────────────────────────────────────────────
wf "$API/src/main/java/com/grash/model/Feature.java" \
'package com.grash.model;

import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.AllArgsConstructor;
import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "features")
@Data
@NoArgsConstructor
@AllArgsConstructor
public class Feature {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(unique = true, nullable = false, length = 100)
    private String code;

    @Column(nullable = false, length = 200)
    private String name;

    @Column(columnDefinition = "TEXT")
    private String description;

    @Column(length = 100)
    private String category;

    @Column(name = "is_active")
    private Boolean isActive = true;

    @Column(name = "created_at")
    private LocalDateTime createdAt = LocalDateTime.now();
}
'

# ── UserFeaturePermission entity ─────────────────────────────────────────────
wf "$API/src/main/java/com/grash/model/UserFeaturePermission.java" \
'package com.grash.model;

import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.AllArgsConstructor;
import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "user_feature_permissions")
@Data
@NoArgsConstructor
@AllArgsConstructor
public class UserFeaturePermission {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne
    @JoinColumn(name = "user_id", nullable = false)
    private OwnUser user;

    @ManyToOne
    @JoinColumn(name = "feature_code", referencedColumnName = "code", nullable = false)
    private Feature feature;

    @Column(name = "is_enabled")
    private Boolean isEnabled = true;

    @ManyToOne
    @JoinColumn(name = "granted_by")
    private OwnUser grantedBy;

    @Column(name = "granted_at")
    private LocalDateTime grantedAt = LocalDateTime.now();

    @Column(columnDefinition = "TEXT")
    private String notes;
}
'

# ── DTOs ─────────────────────────────────────────────────────────────────────
wf "$API/src/main/java/com/grash/dto/SuperAdminCompanyDTO.java" \
'package com.grash.dto;

import lombok.Data;

@Data
public class SuperAdminCompanyDTO {
    private Long id;
    private String name;
    private String email;
    private int userCount;
}
'

wf "$API/src/main/java/com/grash/dto/SuperAdminCompanyDetailDTO.java" \
'package com.grash.dto;

import lombok.Data;
import java.util.Date;
import java.util.List;

@Data
public class SuperAdminCompanyDetailDTO {
    private Long id;
    private String name;
    private String email;
    private Long subscriptionPlanId;
    private String subscriptionPlanName;
    private int usersLimit;
    private int userCount;
    private Date expiryDate;
    private List<SuperAdminUserDTO> users;

    @Data
    public static class SuperAdminUserDTO {
        private Long id;
        private String email;
        private String firstName;
        private String lastName;
        private String role;
    }
}
'

wf "$API/src/main/java/com/grash/dto/SuperAdminInviteUserDTO.java" \
'package com.grash.dto;

import lombok.Data;

@Data
public class SuperAdminInviteUserDTO {
    private String email;
    private Long roleId;
}
'

# ── Repositories ─────────────────────────────────────────────────────────────
wf "$API/src/main/java/com/grash/repository/CompanyFeatureOverrideRepository.java" \
'package com.grash.repository;

import com.grash.model.CompanyFeatureOverride;
import com.grash.model.enums.PlanFeatures;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface CompanyFeatureOverrideRepository extends JpaRepository<CompanyFeatureOverride, Long> {
    List<CompanyFeatureOverride> findByCompanyId(Long companyId);
    Optional<CompanyFeatureOverride> findByCompanyIdAndFeature(Long companyId, PlanFeatures feature);
    void deleteByCompanyIdAndFeature(Long companyId, PlanFeatures feature);
}
'

wf "$API/src/main/java/com/grash/repository/FeatureRepository.java" \
'package com.grash.repository;

import com.grash.model.Feature;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;
import java.util.List;
import java.util.Optional;

@Repository
public interface FeatureRepository extends JpaRepository<Feature, Long> {
    Optional<Feature> findByCode(String code);
    List<Feature> findByIsActiveTrue();
    List<Feature> findByCategory(String category);
    boolean existsByCode(String code);
}
'

wf "$API/src/main/java/com/grash/repository/UserFeaturePermissionRepository.java" \
'package com.grash.repository;

import com.grash.model.UserFeaturePermission;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface UserFeaturePermissionRepository extends JpaRepository<UserFeaturePermission, Long> {
    List<UserFeaturePermission> findByUserId(Long userId);
    Optional<UserFeaturePermission> findByUserIdAndFeatureCode(Long userId, String featureCode);

    @Query("SELECT ufp FROM UserFeaturePermission ufp WHERE ufp.user.id = :userId AND ufp.isEnabled = true")
    List<UserFeaturePermission> findEnabledByUserId(@Param("userId") Long userId);

    void deleteByUserIdAndFeatureCode(Long userId, String featureCode);
    boolean existsByUserIdAndFeatureCode(Long userId, String featureCode);
}
'

ok "Tüm repository'ler oluşturuldu"

# ════════════════════════════════════════════════════════════════════════════
# BÖLÜM 2 – SuperAdminController + UserFeatureController
# ════════════════════════════════════════════════════════════════════════════
hdr "2/8  Backend – SuperAdminController & UserFeatureController"

wf "$API/src/main/java/com/grash/controller/SuperAdminController.java" \
'package com.grash.controller;

import com.grash.dto.SuperAdminCompanyDTO;
import com.grash.dto.SuperAdminCompanyDetailDTO;
import com.grash.dto.AuthResponse;
import com.grash.model.Company;
import com.grash.model.CompanyFeatureOverride;
import com.grash.model.OwnUser;
import com.grash.model.Role;
import com.grash.model.Subscription;
import com.grash.model.SubscriptionPlan;
import com.grash.model.enums.PlanFeatures;
import com.grash.model.enums.RoleCode;
import com.grash.model.enums.RoleType;
import com.grash.repository.CompanyFeatureOverrideRepository;
import com.grash.repository.SubscriptionRepository;
import com.grash.repository.UserRepository;
import com.grash.security.JwtTokenProvider;
import com.grash.service.CompanyService;
import com.grash.service.RoleService;
import com.grash.service.SubscriptionPlanService;
import com.grash.service.CurrencyService;
import com.grash.service.CompanySettingsService;
import com.grash.service.SubscriptionService;
import com.grash.service.UserService;
import com.grash.utils.Utils;
import lombok.Data;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.util.*;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/superadmin")
@PreAuthorize("hasRole('"'"'ROLE_SUPER_ADMIN'"'"')")
@RequiredArgsConstructor
public class SuperAdminController {

    private final CompanyService companyService;
    private final UserRepository userRepository;
    private final UserService userService;
    private final JwtTokenProvider jwtTokenProvider;
    private final SubscriptionPlanService subscriptionPlanService;
    private final CurrencyService currencyService;
    private final CompanySettingsService companySettingsService;
    private final SubscriptionRepository subscriptionRepository;
    private final CompanyFeatureOverrideRepository featureOverrideRepository;
    private final RoleService roleService;
    private final SubscriptionService subscriptionService;
    private final PasswordEncoder passwordEncoder;
    private final Utils utils;

    @GetMapping("/companies")
    public ResponseEntity<List<SuperAdminCompanyDTO>> getAllCompanies() {
        List<Company> all = new ArrayList<>(companyService.getAll());
        List<SuperAdminCompanyDTO> result = all.stream()
                .map(c -> {
                    SuperAdminCompanyDTO dto = new SuperAdminCompanyDTO();
                    dto.setId(c.getId());
                    dto.setName(c.getName());
                    dto.setEmail(c.getEmail());
                    dto.setUserCount(userRepository.findByCompany_Id(c.getId()).size());
                    return dto;
                })
                .collect(Collectors.toList());
        return ResponseEntity.ok(result);
    }

    @GetMapping("/companies/{id}")
    public ResponseEntity<SuperAdminCompanyDetailDTO> getCompanyDetail(@PathVariable Long id) {
        Optional<Company> companyOpt = companyService.findById(id);
        if (!companyOpt.isPresent()) return ResponseEntity.notFound().build();
        Company company = companyOpt.get();
        SuperAdminCompanyDetailDTO dto = new SuperAdminCompanyDetailDTO();
        dto.setId(company.getId());
        dto.setName(company.getName());
        dto.setEmail(company.getEmail());
        if (company.getSubscription() != null) {
            Subscription sub = company.getSubscription();
            dto.setUsersLimit(sub.getUsersCount());
            dto.setExpiryDate(sub.getExpiryDate());
            if (sub.getSubscriptionPlan() != null) {
                dto.setSubscriptionPlanId(sub.getSubscriptionPlan().getId());
                dto.setSubscriptionPlanName(sub.getSubscriptionPlan().getName());
            }
        }
        List<OwnUser> users = new ArrayList<>(userRepository.findByCompany_Id(id));
        dto.setUserCount(users.size());
        dto.setUsers(users.stream().map(u -> {
            SuperAdminCompanyDetailDTO.SuperAdminUserDTO userDTO = new SuperAdminCompanyDetailDTO.SuperAdminUserDTO();
            userDTO.setId(u.getId());
            userDTO.setEmail(u.getEmail());
            userDTO.setFirstName(u.getFirstName());
            userDTO.setLastName(u.getLastName());
            userDTO.setRole(u.getRole() != null ? u.getRole().getName() : null);
            return userDTO;
        }).collect(Collectors.toList()));
        return ResponseEntity.ok(dto);
    }

    @GetMapping("/subscription-plans")
    @Transactional
    public ResponseEntity<List<java.util.Map<String, Object>>> getSubscriptionPlans() {
        List<java.util.Map<String, Object>> plans = new ArrayList<>();
        for (SubscriptionPlan plan : subscriptionPlanService.getAll()) {
            java.util.Map<String, Object> map = new java.util.HashMap<>();
            map.put("id", plan.getId());
            map.put("name", plan.getName());
            map.put("code", plan.getCode());
            plans.add(map);
        }
        return ResponseEntity.ok(plans);
    }

    @PatchMapping("/companies/{id}/plan")
    public ResponseEntity<?> updateCompanyPlan(@PathVariable Long id, @RequestBody PlanUpdateRequest request) {
        Optional<Company> companyOpt = companyService.findById(id);
        if (!companyOpt.isPresent()) return ResponseEntity.notFound().build();
        Optional<SubscriptionPlan> planOpt = subscriptionPlanService.findById(request.getPlanId());
        if (!planOpt.isPresent()) return ResponseEntity.status(HttpStatus.BAD_REQUEST).body("Subscription plan not found");
        Company company = companyOpt.get();
        Subscription subscription = company.getSubscription();
        if (subscription == null) return ResponseEntity.status(HttpStatus.BAD_REQUEST).body("Company has no subscription");
        subscription.setSubscriptionPlan(planOpt.get());
        subscription.setUsersCount(request.getUsersLimit());
        subscriptionRepository.save(subscription);
        return ResponseEntity.ok("{\"success\":true}");
    }

    @Data
    public static class PlanUpdateRequest {
        private Long planId;
        private int usersLimit;
    }

    @PatchMapping("/companies/{id}/expiry")
    public ResponseEntity<?> updateCompanyExpiry(@PathVariable Long id, @RequestBody ExpiryUpdateRequest request) {
        Optional<Company> companyOpt = companyService.findById(id);
        if (!companyOpt.isPresent()) return ResponseEntity.notFound().build();
        Company company = companyOpt.get();
        Subscription subscription = company.getSubscription();
        if (subscription == null) return ResponseEntity.status(HttpStatus.BAD_REQUEST).body("Company has no subscription");
        subscription.setExpiryDate(request.getExpiryDate());
        subscriptionRepository.save(subscription);
        return ResponseEntity.ok().build();
    }

    @Data
    public static class ExpiryUpdateRequest {
        private java.util.Date expiryDate;
    }

    @GetMapping("/companies/{id}/features")
    @Transactional(readOnly = true)
    public ResponseEntity<List<Map<String, Object>>> getCompanyFeatures(@PathVariable Long id) {
        Optional<Company> companyOpt = companyService.findById(id);
        if (!companyOpt.isPresent()) return ResponseEntity.notFound().build();
        Company company = companyOpt.get();
        Set<PlanFeatures> planFeatures = new HashSet<>();
        if (company.getSubscription() != null && company.getSubscription().getSubscriptionPlan() != null) {
            planFeatures.addAll(company.getSubscription().getSubscriptionPlan().getFeatures());
        }
        Map<PlanFeatures, Boolean> overrideMap = new HashMap<>();
        for (CompanyFeatureOverride o : featureOverrideRepository.findByCompanyId(id)) {
            overrideMap.put(o.getFeature(), o.isEnabled());
        }
        List<Map<String, Object>> result = new ArrayList<>();
        for (PlanFeatures feature : PlanFeatures.values()) {
            Map<String, Object> entry = new HashMap<>();
            entry.put("feature", feature.name());
            entry.put("inPlan", planFeatures.contains(feature));
            Boolean override = overrideMap.getOrDefault(feature, null);
            entry.put("override", override);
            boolean effective = override != null ? override : planFeatures.contains(feature);
            entry.put("effective", effective);
            result.add(entry);
        }
        return ResponseEntity.ok(result);
    }

    @PatchMapping("/companies/{id}/features")
    @Transactional
    public ResponseEntity<?> updateCompanyFeature(@PathVariable Long id, @RequestBody FeatureOverrideRequest request) {
        Optional<Company> companyOpt = companyService.findById(id);
        if (!companyOpt.isPresent()) return ResponseEntity.notFound().build();
        Company company = companyOpt.get();
        PlanFeatures feature;
        try {
            feature = PlanFeatures.valueOf(request.getFeature());
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body("Unknown feature: " + request.getFeature());
        }
        if (request.getEnabled() == null) {
            featureOverrideRepository.deleteByCompanyIdAndFeature(id, feature);
        } else {
            Optional<CompanyFeatureOverride> existing = featureOverrideRepository.findByCompanyIdAndFeature(id, feature);
            if (existing.isPresent()) {
                existing.get().setEnabled(request.getEnabled());
                featureOverrideRepository.save(existing.get());
            } else {
                featureOverrideRepository.save(CompanyFeatureOverride.builder()
                        .company(company)
                        .feature(feature)
                        .enabled(request.getEnabled())
                        .build());
            }
        }
        return ResponseEntity.ok("{\"success\":true}");
    }

    @Data
    public static class FeatureOverrideRequest {
        private String feature;
        private Boolean enabled;
    }

    @PostMapping("/switch/{userId}")
    public ResponseEntity<AuthResponse> switchToUser(@PathVariable Long userId) {
        Optional<OwnUser> targetOpt = userService.findById(userId);
        if (!targetOpt.isPresent()) return ResponseEntity.notFound().build();
        OwnUser target = targetOpt.get();
        String token = jwtTokenProvider.createToken(target.getEmail(), List.of(target.getRole().getRoleType()));
        AuthResponse resp = new AuthResponse(token);
        return ResponseEntity.ok(resp);
    }

    // ── Company CRUD ──────────────────────────────────────────────────────────

    @PostMapping("/companies")
    @Transactional
    public ResponseEntity<?> createCompany(@RequestBody CreateCompanyRequest request) {
        Long planId = request.getPlanId();
        SubscriptionPlan plan = planId != null
                ? subscriptionPlanService.findById(planId).orElse(null)
                : subscriptionPlanService.findByCode("BUSINESS").orElse(null);
        if (plan == null) return ResponseEntity.badRequest().body("Subscription plan not found");

        Subscription subscription = Subscription.builder()
                .usersCount(request.getUsersLimit() > 0 ? request.getUsersLimit() : 300)
                .monthly(false)
                .activated(true)
                .startsOn(new java.util.Date())
                .subscriptionPlan(plan)
                .build();
        subscriptionService.create(subscription);

        Company company = new Company(request.getName(), 0, subscription);
        company.setEmail(request.getEmail());
        companyService.create(company);
        currencyService.findByCode("$").ifPresent(currency -> {
            company.getCompanySettings().getGeneralPreferences().setCurrency(currency);
            companySettingsService.update(company.getCompanySettings());
        });

        int userCount = 0;
        if (request.getAdminEmail() != null && !request.getAdminEmail().isBlank()) {
            if (userRepository.existsByEmailIgnoreCase(request.getAdminEmail())) {
                return ResponseEntity.status(HttpStatus.UNPROCESSABLE_ENTITY)
                        .body("Admin email already in use: " + request.getAdminEmail());
            }
            Role adminRole = roleService.findDefaultRoles().stream()
                    .filter(r -> r.getCode() == RoleCode.ADMIN)
                    .findFirst()
                    .orElse(null);
            if (adminRole == null) return ResponseEntity.badRequest().body("Default Administrator role not found");

            OwnUser admin = new OwnUser();
            admin.setEmail(request.getAdminEmail().toLowerCase());
            admin.setFirstName(request.getAdminFirstName() != null ? request.getAdminFirstName() : "");
            admin.setLastName(request.getAdminLastName() != null ? request.getAdminLastName() : "");
            admin.setRole(adminRole);
            admin.setCompany(company);
            admin.setEnabled(true);
            admin.setOwnsCompany(true);
            admin.setUsername(utils.generateStringId());
            String rawPassword = request.getAdminPassword() != null && !request.getAdminPassword().isBlank()
                    ? request.getAdminPassword()
                    : java.util.UUID.randomUUID().toString();
            admin.setPassword(passwordEncoder.encode(rawPassword));
            userRepository.save(admin);
            userCount = 1;
        }

        SuperAdminCompanyDTO dto = new SuperAdminCompanyDTO();
        dto.setId(company.getId());
        dto.setName(company.getName());
        dto.setEmail(company.getEmail());
        dto.setUserCount(userCount);
        return ResponseEntity.ok(dto);
    }

    @DeleteMapping("/companies/{id}")
    @Transactional
    public ResponseEntity<?> deleteCompany(@PathVariable Long id) {
        if (!companyService.findById(id).isPresent()) return ResponseEntity.notFound().build();
        companyService.delete(id);
        return ResponseEntity.ok().build();
    }

    @PatchMapping("/companies/{id}/info")
    @Transactional
    public ResponseEntity<?> updateCompanyInfo(@PathVariable Long id, @RequestBody UpdateCompanyInfoRequest request) {
        Optional<Company> companyOpt = companyService.findById(id);
        if (!companyOpt.isPresent()) return ResponseEntity.notFound().build();
        Company company = companyOpt.get();
        if (request.getName() != null) company.setName(request.getName());
        if (request.getEmail() != null) company.setEmail(request.getEmail());
        companyService.update(company);
        return ResponseEntity.ok().build();
    }

    @Data
    public static class CreateCompanyRequest {
        private String name;
        private String email;
        private Long planId;
        private int usersLimit;
        private String adminFirstName;
        private String adminLastName;
        private String adminEmail;
        private String adminPassword;
    }

    @Data
    public static class UpdateCompanyInfoRequest {
        private String name;
        private String email;
    }

    // ── User management ───────────────────────────────────────────────────────

    @GetMapping("/companies/{id}/roles")
    @Transactional(readOnly = true)
    public ResponseEntity<List<Map<String, Object>>> getCompanyRoles(@PathVariable Long id) {
        if (!companyService.findById(id).isPresent()) return ResponseEntity.notFound().build();
        List<Map<String, Object>> result = new ArrayList<>();
        for (Role role : roleService.findByCompany(id)) {
            Map<String, Object> m = new HashMap<>();
            m.put("id", role.getId());
            m.put("name", role.getName());
            m.put("roleType", role.getRoleType().name());
            result.add(m);
        }
        return ResponseEntity.ok(result);
    }

    @PostMapping("/companies/{id}/users")
    @Transactional
    public ResponseEntity<?> addUserToCompany(@PathVariable Long id, @RequestBody AddUserRequest request) {
        Optional<Company> companyOpt = companyService.findById(id);
        if (!companyOpt.isPresent()) return ResponseEntity.notFound().build();
        Company company = companyOpt.get();
        if (userRepository.existsByEmailIgnoreCase(request.getEmail())) {
            return ResponseEntity.status(HttpStatus.UNPROCESSABLE_ENTITY).body("Email already in use");
        }
        Optional<Role> roleOpt = roleService.findById(request.getRoleId());
        if (!roleOpt.isPresent()) return ResponseEntity.badRequest().body("Role not found");

        OwnUser user = new OwnUser();
        user.setEmail(request.getEmail().toLowerCase());
        user.setFirstName(request.getFirstName() != null ? request.getFirstName() : "");
        user.setLastName(request.getLastName() != null ? request.getLastName() : "");
        user.setRole(roleOpt.get());
        user.setCompany(company);
        user.setEnabled(true);
        user.setUsername(utils.generateStringId());
        String rawPwd = request.getPassword() != null && !request.getPassword().isBlank()
                ? request.getPassword()
                : java.util.UUID.randomUUID().toString();
        user.setPassword(passwordEncoder.encode(rawPwd));
        OwnUser saved = userRepository.save(user);

        SuperAdminCompanyDetailDTO.SuperAdminUserDTO dto = new SuperAdminCompanyDetailDTO.SuperAdminUserDTO();
        dto.setId(saved.getId());
        dto.setEmail(saved.getEmail());
        dto.setFirstName(saved.getFirstName());
        dto.setLastName(saved.getLastName());
        dto.setRole(saved.getRole().getName());
        return ResponseEntity.ok(dto);
    }

    @DeleteMapping("/companies/{id}/users/{userId}")
    @Transactional
    public ResponseEntity<?> removeUserFromCompany(@PathVariable Long id, @PathVariable Long userId) {
        Optional<OwnUser> userOpt = userRepository.findByIdAndCompany_Id(userId, id);
        if (!userOpt.isPresent()) return ResponseEntity.notFound().build();
        userRepository.delete(userOpt.get());
        return ResponseEntity.ok().build();
    }

    @PatchMapping("/companies/{id}/users/{userId}/role")
    @Transactional
    public ResponseEntity<?> changeUserRole(@PathVariable Long id, @PathVariable Long userId,
                                            @RequestBody ChangeRoleRequest request) {
        Optional<OwnUser> userOpt = userRepository.findByIdAndCompany_Id(userId, id);
        if (!userOpt.isPresent()) return ResponseEntity.notFound().build();
        Optional<Role> roleOpt = roleService.findById(request.getRoleId());
        if (!roleOpt.isPresent()) return ResponseEntity.badRequest().body("Role not found");
        OwnUser user = userOpt.get();
        user.setRole(roleOpt.get());
        userRepository.save(user);
        return ResponseEntity.ok().build();
    }

    @PatchMapping("/companies/{id}/users/{userId}/password")
    @Transactional
    public ResponseEntity<?> changeUserPassword(@PathVariable Long id, @PathVariable Long userId,
                                                @RequestBody ChangePasswordRequest request) {
        if (request.getNewPassword() == null || request.getNewPassword().isBlank()) {
            return ResponseEntity.badRequest().body("Password cannot be empty");
        }
        Optional<OwnUser> userOpt = userRepository.findByIdAndCompany_Id(userId, id);
        if (!userOpt.isPresent()) return ResponseEntity.notFound().build();
        OwnUser user = userOpt.get();
        user.setPassword(passwordEncoder.encode(request.getNewPassword()));
        userRepository.save(user);
        return ResponseEntity.ok().build();
    }

    @Data public static class AddUserRequest {
        private String email; private String firstName; private String lastName;
        private Long roleId; private String password;
    }
    @Data public static class ChangeRoleRequest { private Long roleId; }
    @Data public static class ChangePasswordRequest { private String newPassword; }
}
'

wf "$API/src/main/java/com/grash/controller/UserFeatureController.java" \
'package com.grash.controller;

import com.grash.model.Feature;
import com.grash.model.OwnUser;
import com.grash.model.UserFeaturePermission;
import com.grash.repository.FeatureRepository;
import com.grash.repository.UserFeaturePermissionRepository;
import com.grash.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.*;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/user-features")
@RequiredArgsConstructor
public class UserFeatureController {

    private final UserFeaturePermissionRepository permissionRepository;
    private final FeatureRepository featureRepository;
    private final UserRepository userRepository;

    @GetMapping("/user/{userId}")
    public ResponseEntity<Map<String, Object>> getUserFeatures(@PathVariable Long userId) {
        List<UserFeaturePermission> permissions = permissionRepository.findByUserId(userId);
        List<Feature> allFeatures = featureRepository.findByIsActiveTrue();
        Map<String, Object> response = new HashMap<>();
        if (permissions.isEmpty()) {
            Map<String, Boolean> features = allFeatures.stream()
                .collect(Collectors.toMap(Feature::getCode, f -> true));
            response.put("features", features);
            response.put("hasCustomPermissions", false);
        } else {
            Map<String, Boolean> features = permissions.stream()
                .collect(Collectors.toMap(p -> p.getFeature().getCode(), UserFeaturePermission::getIsEnabled));
            response.put("features", features);
            response.put("hasCustomPermissions", true);
        }
        response.put("userId", userId);
        return ResponseEntity.ok(response);
    }

    @PostMapping("/user/{userId}/feature/{featureCode}")
    public ResponseEntity<UserFeaturePermission> setUserFeature(
            @PathVariable Long userId, @PathVariable String featureCode,
            @RequestParam Boolean enabled) {
        OwnUser user = userRepository.findById(userId)
            .orElseThrow(() -> new RuntimeException("User not found"));
        Feature feature = featureRepository.findByCode(featureCode)
            .orElseThrow(() -> new RuntimeException("Feature not found"));
        Optional<UserFeaturePermission> existing = permissionRepository.findByUserIdAndFeatureCode(userId, featureCode);
        UserFeaturePermission permission;
        if (existing.isPresent()) {
            permission = existing.get();
            permission.setIsEnabled(enabled);
        } else {
            permission = new UserFeaturePermission();
            permission.setUser(user);
            permission.setFeature(feature);
            permission.setIsEnabled(enabled);
        }
        return ResponseEntity.ok(permissionRepository.save(permission));
    }

    @DeleteMapping("/user/{userId}/reset")
    public ResponseEntity<?> resetUserPermissions(@PathVariable Long userId) {
        List<UserFeaturePermission> permissions = permissionRepository.findByUserId(userId);
        permissionRepository.deleteAll(permissions);
        Map<String, Object> response = new HashMap<>();
        response.put("message", "All custom permissions removed.");
        response.put("deletedCount", permissions.size());
        return ResponseEntity.ok(response);
    }

    @GetMapping("/features")
    public ResponseEntity<List<Feature>> getAllFeatures() {
        return ResponseEntity.ok(featureRepository.findByIsActiveTrue());
    }

    @GetMapping("/user/{userId}/can-access/{featureCode}")
    public ResponseEntity<Boolean> canAccess(@PathVariable Long userId, @PathVariable String featureCode) {
        Optional<UserFeaturePermission> permission = permissionRepository.findByUserIdAndFeatureCode(userId, featureCode);
        return ResponseEntity.ok(permission.map(UserFeaturePermission::getIsEnabled).orElse(true));
    }
}
'

ok "SuperAdminController ve UserFeatureController yazıldı"

# ════════════════════════════════════════════════════════════════════════════
# BÖLÜM 3 – Mevcut Java dosyalarını patch'le
# ════════════════════════════════════════════════════════════════════════════
hdr "3/8  Backend – Mevcut Java dosyaları patch"

# ── Subscription.java: expiryDate alanı ekle ────────────────────────────────
python3 - "$API/src/main/java/com/grash/model/Subscription.java" << 'PYEOF'
import sys, re

path = sys.argv[1]
with open(path) as f:
    src = f.read()

# Zaten patch'li mi?
if 'expiryDate' in src:
    print(f"  [SKIP] {path} (expiryDate zaten mevcut)")
    sys.exit(0)

# private Date endsOn; satırından sonra ekle
insert = '\n    /** Superadmin tarafından ayarlanan bitiş tarihi. Dolunca erişim kapanır. */\n    private Date expiryDate;\n'
new_src = re.sub(r'(private Date endsOn;)', r'\1' + insert, src)
if new_src == src:
    # Alternatif: scheduledChangeType sonrasına ekle
    new_src = re.sub(
        r'(private SubscriptionScheduledChangeType scheduledChangeType;)',
        r'\1' + insert,
        src
    )

with open(path, 'w') as f:
    f.write(new_src)
print(f"  ✓ {path} (expiryDate eklendi)")
PYEOF

# ── UserService.java: checkUsageBasedLimit boşalt + signin expiry check ──────
python3 - "$API/src/main/java/com/grash/service/UserService.java" << 'PYEOF'
import sys, re

path = sys.argv[1]
with open(path) as f:
    src = f.read()

changed = False

# 1) checkUsageBasedLimit metodunu boşalt
pattern_limit = r'(public void checkUsageBasedLimit\(int newUsersCount\)\s*\{)[^}]*(})'
replacement_limit = r'\1\n        // License check disabled\n    \2'
new_src = re.sub(pattern_limit, replacement_limit, src)
if new_src != src:
    src = new_src
    changed = True
    print(f"  ✓ checkUsageBasedLimit boşaltıldı")
else:
    print(f"  [SKIP] checkUsageBasedLimit zaten düzenlendi veya bulunamadı")

# 2) signin() içine expiry check ekle (user.setLastLogin'den önce)
expiry_block = '''
            boolean isNonSuperAdmin = user.getRole() != null && !user.getRole().getRoleType().name().equals("ROLE_SUPER_ADMIN");
            if (isNonSuperAdmin && user.getCompany() != null && user.getCompany().getSubscription() != null) {
                Date expiryDate = user.getCompany().getSubscription().getExpiryDate();
                if (expiryDate != null && expiryDate.before(new Date())) {
                    throw new CustomException("Subscription expired", HttpStatus.FORBIDDEN);
                }
            }
'''

if 'expiryDate.before(new Date())' in src:
    print(f"  [SKIP] expiry check zaten mevcut")
else:
    # setLastLogin öncesine ekle
    new_src = re.sub(
        r'(\s*user\.setLastLogin\(new Date\(\)\);)',
        expiry_block + r'\1',
        src,
        count=1
    )
    if new_src != src:
        src = new_src
        changed = True
        print(f"  ✓ expiry check eklendi (signin)")
    else:
        print(f"  [WARN] setLastLogin bulunamadı — expiry check EKLENMEDI")

if changed:
    with open(path, 'w') as f:
        f.write(src)
PYEOF

ok "Java patch işlemleri tamamlandı"

# ════════════════════════════════════════════════════════════════════════════
# BÖLÜM 4 – DB Migration dosyaları
# ════════════════════════════════════════════════════════════════════════════
hdr "4/8  DB Migrations"

mkdir -p "$CHANGELOG"

# ── 2026_03_31: company activation flags ────────────────────────────────────
cat > "$CHANGELOG/2026_03_31_1775000000_add_company_activation_flags.xml" << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<databaseChangeLog
        xmlns="http://www.liquibase.org/xml/ns/dbchangelog"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:schemaLocation="http://www.liquibase.org/xml/ns/dbchangelog
        http://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-3.4.xsd">

    <changeSet id="2026_03_31_1775000000" author="intercom-activation">
        <addColumn tableName="company">
            <column name="first_work_order_created" type="boolean" defaultValueBoolean="false">
                <constraints nullable="false"/>
            </column>
            <column name="invited_users" type="boolean" defaultValueBoolean="false">
                <constraints nullable="false"/>
            </column>
            <column name="imported_assets" type="boolean" defaultValueBoolean="false">
                <constraints nullable="false"/>
            </column>
        </addColumn>
    </changeSet>

</databaseChangeLog>
XMLEOF
ok "2026_03_31_1775000000_add_company_activation_flags.xml"

# ── 2026_04_02: api_key tablosu ──────────────────────────────────────────────
cat > "$CHANGELOG/2026_04_02_00000000001_add_api_key.xml" << 'XMLEOF'
<databaseChangeLog
        xmlns="http://www.liquibase.org/xml/ns/dbchangelog"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:schemaLocation="http://www.liquibase.org/xml/ns/dbchangelog
        http://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-4.3.xsd">

    <changeSet id="2026_04_02_api_key_00000000001" author="Ibrahima">
        <createTable tableName="api_key">
            <column name="id" type="bigint" autoIncrement="true">
                <constraints primaryKey="true" nullable="false"/>
            </column>
            <column name="label" type="VARCHAR(255)">
                <constraints nullable="false"/>
            </column>
            <column name="code" type="VARCHAR(500)">
                <constraints nullable="false"/>
            </column>
            <column name="user_id" type="BIGINT">
                <constraints nullable="false" foreignKeyName="fk_api_key_user" references="own_user(id)"
                             deleteCascade="true"/>
            </column>
            <column name="company_id" type="BIGINT">
                <constraints nullable="false" foreignKeyName="fk_api_key_company" references="company(id)"
                             deleteCascade="true"/>
            </column>
            <column name="last_used" type="TIMESTAMP"/>
            <column name="created_at" type="TIMESTAMP"><constraints nullable="false"/></column>
            <column name="updated_at" type="TIMESTAMP"><constraints nullable="false"/></column>
            <column name="created_by" type="BIGINT"/>
            <column name="updated_by" type="BIGINT"/>
        </createTable>
    </changeSet>
    <changeSet id="1775168975944-1" author="Ibrahima G. Coulibaly">
        <createSequence sequenceName="api_key_seq" startValue="1" incrementBy="50"/>
    </changeSet>
</databaseChangeLog>
XMLEOF
ok "2026_04_02_00000000001_add_api_key.xml"

# ── 2026_04_05: company_feature_override tablosu ─────────────────────────────
cat > "$CHANGELOG/2026_04_05_1744000000_company_feature_overrides.xml" << 'XMLEOF'
<databaseChangeLog
        xmlns="http://www.liquibase.org/xml/ns/dbchangelog"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:schemaLocation="http://www.liquibase.org/xml/ns/dbchangelog
        http://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-4.3.xsd">

    <changeSet id="2026_04_05_company_feature_overrides_01" author="atlas">
        <createTable tableName="company_feature_override">
            <column name="id" type="bigint" autoIncrement="true">
                <constraints primaryKey="true" nullable="false"/>
            </column>
            <column name="company_id" type="BIGINT">
                <constraints nullable="false" foreignKeyName="fk_cfo_company" references="company(id)"
                             deleteCascade="true"/>
            </column>
            <column name="feature" type="VARCHAR(100)"><constraints nullable="false"/></column>
            <column name="enabled" type="BOOLEAN"><constraints nullable="false"/></column>
            <column name="created_at" type="TIMESTAMP"><constraints nullable="false"/></column>
            <column name="updated_at" type="TIMESTAMP"><constraints nullable="false"/></column>
            <column name="created_by" type="BIGINT"/>
            <column name="updated_by" type="BIGINT"/>
        </createTable>
        <addUniqueConstraint tableName="company_feature_override"
                             columnNames="company_id, feature"
                             constraintName="uq_company_feature_override"/>
    </changeSet>
    <changeSet id="2026_04_05_company_feature_overrides_seq" author="atlas">
        <createSequence sequenceName="company_feature_override_seq" startValue="1" incrementBy="50"/>
    </changeSet>

</databaseChangeLog>
XMLEOF
ok "2026_04_05_1744000000_company_feature_overrides.xml"

# ── 2026_04_05: subscription expiry_date ─────────────────────────────────────
cat > "$CHANGELOG/2026_04_05_1744000001_subscription_expiry_date.xml" << 'XMLEOF'
<databaseChangeLog
        xmlns="http://www.liquibase.org/xml/ns/dbchangelog"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:schemaLocation="http://www.liquibase.org/xml/ns/dbchangelog
        http://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-4.3.xsd">

    <changeSet id="2026_04_05_subscription_expiry_date_01" author="atlas">
        <addColumn tableName="subscription">
            <column name="expiry_date" type="TIMESTAMP"/>
        </addColumn>
    </changeSet>

</databaseChangeLog>
XMLEOF
ok "2026_04_05_1744000001_subscription_expiry_date.xml"

# ── 2026_04_09: features tablosu ─────────────────────────────────────────────
cat > "$CHANGELOG/2026_04_09_0001_create_features_table.xml" << 'XMLEOF'
<databaseChangeLog
        xmlns="http://www.liquibase.org/xml/ns/dbchangelog"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:schemaLocation="http://www.liquibase.org/xml/ns/dbchangelog
        http://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-4.3.xsd">

    <changeSet id="2026_04_09_create_features_01" author="atlas">
        <createTable tableName="features">
            <column name="id" type="bigint" autoIncrement="true">
                <constraints primaryKey="true" nullable="false"/>
            </column>
            <column name="code" type="VARCHAR(100)">
                <constraints nullable="false" unique="true" uniqueConstraintName="uq_feature_code"/>
            </column>
            <column name="name" type="VARCHAR(200)"><constraints nullable="false"/></column>
            <column name="description" type="TEXT"/>
            <column name="category" type="VARCHAR(100)"/>
            <column name="is_active" type="BOOLEAN" defaultValueBoolean="true"/>
            <column name="created_at" type="TIMESTAMP"/>
        </createTable>
    </changeSet>

</databaseChangeLog>
XMLEOF
ok "2026_04_09_0001_create_features_table.xml"

# ── 2026_04_09: user_feature_permissions tablosu ─────────────────────────────
cat > "$CHANGELOG/2026_04_09_0002_create_user_feature_permissions.xml" << 'XMLEOF'
<databaseChangeLog
        xmlns="http://www.liquibase.org/xml/ns/dbchangelog"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:schemaLocation="http://www.liquibase.org/xml/ns/dbchangelog
        http://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-4.3.xsd">

    <changeSet id="2026_04_09_create_user_feature_permissions_01" author="atlas">
        <createTable tableName="user_feature_permissions">
            <column name="id" type="bigint" autoIncrement="true">
                <constraints primaryKey="true" nullable="false"/>
            </column>
            <column name="user_id" type="BIGINT">
                <constraints nullable="false" foreignKeyName="fk_ufp_user" references="own_user(id)"
                             deleteCascade="true"/>
            </column>
            <column name="feature_code" type="VARCHAR(100)">
                <constraints nullable="false" foreignKeyName="fk_ufp_feature" references="features(code)"/>
            </column>
            <column name="is_enabled" type="BOOLEAN" defaultValueBoolean="true"/>
            <column name="granted_by" type="BIGINT">
                <constraints foreignKeyName="fk_ufp_granted_by" references="own_user(id)"
                             deleteCascade="false"/>
            </column>
            <column name="granted_at" type="TIMESTAMP"/>
            <column name="notes" type="TEXT"/>
        </createTable>
        <addUniqueConstraint tableName="user_feature_permissions"
                             columnNames="user_id, feature_code"
                             constraintName="uq_user_feature_permission"/>
    </changeSet>

</databaseChangeLog>
XMLEOF
ok "2026_04_09_0002_create_user_feature_permissions.xml"

# ── master.xml güncelle ───────────────────────────────────────────────────────
hdr "4b/8  master.xml güncelleniyor"

python3 - "$MASTER" << 'PYEOF'
import sys

path = sys.argv[1]
with open(path) as f:
    src = f.read()

new_entries = [
    'changelog/2026_03_31_1775000000_add_company_activation_flags.xml',
    'changelog/2026_04_02_00000000001_add_api_key.xml',
    'changelog/2026_04_05_1744000000_company_feature_overrides.xml',
    'changelog/2026_04_05_1744000001_subscription_expiry_date.xml',
    'changelog/2026_04_09_0001_create_features_table.xml',
    'changelog/2026_04_09_0002_create_user_feature_permissions.xml',
]

added = []
for entry in new_entries:
    if entry in src:
        print(f"  [SKIP] {entry} zaten mevcut")
        continue
    include_line = f'    <include file="{entry}"\n             relativeToChangelogFile="true"/>'
    src = src.replace('</databaseChangeLog>', include_line + '\n</databaseChangeLog>')
    added.append(entry)
    print(f"  ✓ {entry} eklendi")

with open(path, 'w') as f:
    f.write(src)

if not added:
    print("  Tüm migration'lar zaten master.xml'de mevcut")
PYEOF

# ════════════════════════════════════════════════════════════════════════════
# BÖLÜM 5 – Frontend: Yeni dosyalar
# ════════════════════════════════════════════════════════════════════════════
hdr "5/8  Frontend – Yeni TSX/TS dosyaları"

mkdir -p "$FE/src/content/own/SuperAdmin"
mkdir -p "$FE/src/components/SuperAdmin"

# ── useLicenseEntitlement hook ───────────────────────────────────────────────
wf "$FE/src/hooks/useLicenseEntitlement.ts" \
"import { LicenseEntitlement } from '../models/owns/license';
import { PlanFeature } from '../models/owns/subscriptionPlan';
import useAuth from './useAuth';

const entitlementToPlanFeature: Record<string, PlanFeature> = {
  'WORK_ORDER_HISTORY': PlanFeature.CHECKLIST,
  'WORKFLOW': PlanFeature.WORKFLOW,
  'NFC_BARCODE': PlanFeature.METER,
  'FILE_ATTACHMENTS': PlanFeature.FILE,
  'TIME_TRACKING': PlanFeature.ADDITIONAL_TIME,
  'COST_TRACKING': PlanFeature.ADDITIONAL_COST,
  'SIGNATURE_CAPTURE': PlanFeature.SIGNATURE,
  'CUSTOM_ROLES': PlanFeature.ROLE,
  'CONDITION_BASED_PM': PlanFeature.METER,
  'CUSTOMER_VENDOR': PlanFeature.REQUEST_CONFIGURATION,
  'FIELD_CONFIGURATION': PlanFeature.REQUEST_CONFIGURATION,
  'ADVANCED_ANALYTICS': PlanFeature.ANALYTICS,
  'API_ACCESS': PlanFeature.API_ACCESS,
  'WORK_ORDER_LINKING': PlanFeature.PURCHASE_ORDER,
};

export const useLicenseEntitlement = (entitlement: LicenseEntitlement) => {
  const { hasFeature, user } = useAuth();

  if (user?.role?.roleType === 'ROLE_SUPER_ADMIN') return true;

  const planFeature = entitlementToPlanFeature[entitlement];
  if (!planFeature) return true;

  return hasFeature(planFeature);
};
"

# ── UserFeatureManagement bileşeni ───────────────────────────────────────────
wf "$FE/src/components/SuperAdmin/UserFeatureManagement.tsx" \
"import React, { useState, useEffect } from 'react';
import {
  Box, Card, CardContent, Typography, Table, TableBody,
  TableCell, TableHead, TableRow, Switch, Button, Alert,
  CircularProgress, Chip, FormControlLabel,
} from '@mui/material';
import api from 'src/utils/api';

interface Feature {
  id: number; code: string; name: string;
  description: string; category: string; isActive: boolean;
}

interface UserFeaturesResponse {
  features: Record<string, boolean>;
  hasCustomPermissions: boolean;
}

interface UserFeatureManagementProps { userId: number; userName?: string; }

const UserFeatureManagement: React.FC<UserFeatureManagementProps> = ({ userId, userName }) => {
  const [features, setFeatures] = useState<Feature[]>([]);
  const [userFeatures, setUserFeatures] = useState<Record<string, boolean>>({});
  const [hasCustomPermissions, setHasCustomPermissions] = useState(false);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  useEffect(() => { fetchData(); }, [userId]);

  const fetchData = async () => {
    setLoading(true);
    try {
      const featuresData = await api.get<Feature[]>('api/user-features/features');
      setFeatures(featuresData);
      const userData = await api.get<UserFeaturesResponse>(\`api/user-features/user/\${userId}\`);
      setUserFeatures(userData.features);
      setHasCustomPermissions(userData.hasCustomPermissions);
    } catch { setError('Veriler yüklenirken hata oluştu'); }
    finally { setLoading(false); }
  };

  const handleFeatureToggle = async (featureCode: string, enabled: boolean) => {
    setSaving(true); setError(null); setSuccess(null);
    try {
      await api.post(\`api/user-features/user/\${userId}/feature/\${featureCode}?enabled=\${enabled}\`, null);
      setUserFeatures((prev) => ({ ...prev, [featureCode]: enabled }));
      setHasCustomPermissions(true);
      setSuccess('Özellik güncellendi');
    } catch { setError('Güncelleme başarısız'); }
    finally { setSaving(false); }
  };

  const handleResetPermissions = async () => {
    if (!window.confirm('Tüm özel izinler silinecek. Emin misiniz?')) return;
    setSaving(true); setError(null); setSuccess(null);
    try {
      await api.deletes(\`api/user-features/user/\${userId}/reset\`);
      const allEnabled: Record<string, boolean> = {};
      features.forEach((f) => { allEnabled[f.code] = true; });
      setUserFeatures(allEnabled);
      setHasCustomPermissions(false);
      setSuccess('Kullanıcı varsayılan izinlere döndürüldü');
    } catch { setError('Sıfırlama başarısız'); }
    finally { setSaving(false); }
  };

  const getCategoryColor = (category: string) => {
    switch (category) {
      case 'Core': return 'primary';
      case 'Advanced': return 'secondary';
      case 'Premium': return 'warning';
      default: return 'default';
    }
  };

  const groupedFeatures = features.reduce((acc, feature) => {
    const category = feature.category || 'Other';
    if (!acc[category]) acc[category] = [];
    acc[category].push(feature);
    return acc;
  }, {} as Record<string, Feature[]>);

  if (loading) return <Box sx={{ display: 'flex', justifyContent: 'center', p: 4 }}><CircularProgress /></Box>;

  return (
    <Box sx={{ p: 3 }}>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 3, alignItems: 'center' }}>
        <Box>
          <Typography variant=\"h5\">Kullanıcı Özellik Yönetimi</Typography>
          {userName && <Typography variant=\"body2\" color=\"text.secondary\">{userName}</Typography>}
        </Box>
        {hasCustomPermissions && (
          <Button variant=\"outlined\" color=\"warning\" onClick={handleResetPermissions} disabled={saving}>
            Varsayılana Döndür
          </Button>
        )}
      </Box>
      {!hasCustomPermissions && (
        <Alert severity=\"info\" sx={{ mb: 2 }}>Bu kullanıcı varsayılan izinlere sahip (tüm özellikler açık).</Alert>
      )}
      {error && <Alert severity=\"error\" sx={{ mb: 2 }} onClose={() => setError(null)}>{error}</Alert>}
      {success && <Alert severity=\"success\" sx={{ mb: 2 }} onClose={() => setSuccess(null)}>{success}</Alert>}
      {Object.entries(groupedFeatures).map(([category, categoryFeatures]) => (
        <Card key={category} sx={{ mb: 2 }}>
          <CardContent>
            <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
              <Typography variant=\"h6\" sx={{ mr: 2 }}>{category}</Typography>
              <Chip label={\`\${categoryFeatures.length} özellik\`} size=\"small\" color={getCategoryColor(category) as any} />
            </Box>
            <Table size=\"small\">
              <TableHead>
                <TableRow>
                  <TableCell>Özellik</TableCell>
                  <TableCell>Açıklama</TableCell>
                  <TableCell align=\"center\">Durum</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {categoryFeatures.map((feature) => {
                  const isEnabled = userFeatures[feature.code] !== false;
                  return (
                    <TableRow key={feature.code}>
                      <TableCell><Typography variant=\"body2\" fontWeight=\"medium\">{feature.name}</Typography></TableCell>
                      <TableCell><Typography variant=\"body2\" color=\"text.secondary\">{feature.description}</Typography></TableCell>
                      <TableCell align=\"center\">
                        <FormControlLabel
                          control={<Switch checked={isEnabled} onChange={(e) => handleFeatureToggle(feature.code, e.target.checked)} disabled={saving} />}
                          label={isEnabled ? 'Açık' : 'Kapalı'}
                        />
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </CardContent>
        </Card>
      ))}
    </Box>
  );
};

export default UserFeatureManagement;
"

ok "useLicenseEntitlement.ts ve UserFeatureManagement.tsx yazıldı"

# ════════════════════════════════════════════════════════════════════════════
# BÖLÜM 6 – SuperAdmin sayfaları (Companies.tsx ve CompanyDetail.tsx)
# ════════════════════════════════════════════════════════════════════════════
hdr "6/8  Frontend – SuperAdmin sayfaları"

# Companies.tsx dosyasını Python ile yaz (tek tırnak çakışmasını önlemek için)
python3 - "$FE/src/content/own/SuperAdmin/Companies.tsx" << 'PYEOF'
import sys, os
content = r"""import {
  Alert, Box, Button, Card, CardContent, Chip, CircularProgress,
  Container, Dialog, DialogActions, DialogContent, DialogTitle,
  Table, TableBody, TableCell, TableHead, TableRow, TextField, Typography
} from '@mui/material';
import { useEffect, useState } from 'react';
import { Helmet } from 'react-helmet-async';
import { useNavigate } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import PageTitleWrapper from 'src/components/PageTitleWrapper';
import api from 'src/utils/api';
import { format } from 'date-fns';

interface SuperAdminCompanyDTO {
  id: number; name: string; email: string;
  createdAt: string; subscriptionPlanName: string | null; userCount: number;
}

function SuperAdminCompanies() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const [companies, setCompanies] = useState<SuperAdminCompanyDTO[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [createOpen, setCreateOpen] = useState(false);
  const [createName, setCreateName] = useState('');
  const [createEmail, setCreateEmail] = useState('');
  const [adminFirstName, setAdminFirstName] = useState('');
  const [adminLastName, setAdminLastName] = useState('');
  const [adminEmail, setAdminEmail] = useState('');
  const [adminPassword, setAdminPassword] = useState('');
  const [creating, setCreating] = useState(false);

  const [deleteTarget, setDeleteTarget] = useState<SuperAdminCompanyDTO | null>(null);
  const [deleting, setDeleting] = useState(false);

  useEffect(() => {
    api.get<SuperAdminCompanyDTO[]>('superadmin/companies')
      .then(setCompanies)
      .finally(() => setLoading(false));
  }, []);

  const handleCreate = async () => {
    if (!createName.trim()) return;
    setCreating(true); setError(null);
    try {
      const created = await api.post<SuperAdminCompanyDTO>('superadmin/companies', {
        name: createName.trim(), email: createEmail.trim(),
        adminFirstName: adminFirstName.trim(), adminLastName: adminLastName.trim(),
        adminEmail: adminEmail.trim(), adminPassword
      });
      setCompanies((prev) => [...prev, created]);
      setCreateOpen(false);
      setCreateName(''); setCreateEmail(''); setAdminFirstName('');
      setAdminLastName(''); setAdminEmail(''); setAdminPassword('');
    } catch { setError('Şirket oluşturulamadı'); }
    finally { setCreating(false); }
  };

  const handleDelete = async () => {
    if (!deleteTarget) return;
    setDeleting(true); setError(null);
    try {
      await api.deletes(`superadmin/companies/${deleteTarget.id}`);
      setCompanies((prev) => prev.filter((c) => c.id !== deleteTarget.id));
      setDeleteTarget(null);
    } catch { setError('Şirket silinemedi'); }
    finally { setDeleting(false); }
  };

  return (
    <>
      <Helmet><title>Superadmin - {t('companies')}</title></Helmet>
      <PageTitleWrapper>
        <Box display="flex" justifyContent="space-between" alignItems="center">
          <Typography variant="h2">{t('companies')}</Typography>
          <Button variant="contained" onClick={() => setCreateOpen(true)}>+ Yeni Şirket</Button>
        </Box>
      </PageTitleWrapper>
      <Container maxWidth="lg">
        {error && <Alert severity="error" sx={{ mb: 2 }}>{error}</Alert>}
        <Card>
          <CardContent>
            {loading ? (
              <Box display="flex" justifyContent="center" p={4}><CircularProgress /></Box>
            ) : companies.length === 0 ? (
              <Typography color="text.secondary" p={2}>{t('no_companies')}</Typography>
            ) : (
              <Table>
                <TableHead>
                  <TableRow>
                    <TableCell><b>{t('name')}</b></TableCell>
                    <TableCell><b>{t('email')}</b></TableCell>
                    <TableCell><b>{t('subscription_plan')}</b></TableCell>
                    <TableCell><b>{t('user_count')}</b></TableCell>
                    <TableCell><b>{t('created_at')}</b></TableCell>
                    <TableCell />
                  </TableRow>
                </TableHead>
                <TableBody>
                  {companies.map((c) => (
                    <TableRow key={c.id} hover>
                      <TableCell>{c.name || '-'}</TableCell>
                      <TableCell>{c.email || '-'}</TableCell>
                      <TableCell>
                        {c.subscriptionPlanName
                          ? <Chip label={c.subscriptionPlanName} size="small" color="primary" variant="outlined" />
                          : '-'}
                      </TableCell>
                      <TableCell>{c.userCount}</TableCell>
                      <TableCell>{c.createdAt ? format(new Date(c.createdAt), 'dd.MM.yyyy') : '-'}</TableCell>
                      <TableCell>
                        <Box display="flex" gap={1}>
                          <Button variant="outlined" size="small"
                            onClick={() => navigate(`/app/superadmin/companies/${c.id}`)}>
                            {t('details')}
                          </Button>
                          <Button variant="outlined" size="small" color="error"
                            onClick={() => setDeleteTarget(c)}>Sil</Button>
                        </Box>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>
      </Container>

      <Dialog open={createOpen} onClose={() => setCreateOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>Yeni Şirket Oluştur</DialogTitle>
        <DialogContent>
          <Typography variant="subtitle2" color="text.secondary" sx={{ mt: 1, mb: 0.5 }}>Şirket Bilgileri</Typography>
          <TextField label="Şirket Adı *" fullWidth margin="dense" autoFocus value={createName}
            onChange={(e) => setCreateName(e.target.value)} />
          <TextField label="Şirket E-postası" fullWidth margin="dense" type="email" value={createEmail}
            onChange={(e) => setCreateEmail(e.target.value)} />
          <Typography variant="subtitle2" color="text.secondary" sx={{ mt: 2, mb: 0.5 }}>Admin Kullanıcı (isteğe bağlı)</Typography>
          <Box display="flex" gap={1}>
            <TextField label="Ad" fullWidth margin="dense" value={adminFirstName}
              onChange={(e) => setAdminFirstName(e.target.value)} />
            <TextField label="Soyad" fullWidth margin="dense" value={adminLastName}
              onChange={(e) => setAdminLastName(e.target.value)} />
          </Box>
          <TextField label="Admin E-postası" fullWidth margin="dense" type="email" value={adminEmail}
            onChange={(e) => setAdminEmail(e.target.value)} />
          <TextField label="Admin Şifresi" fullWidth margin="dense" type="password" value={adminPassword}
            onChange={(e) => setAdminPassword(e.target.value)}
            helperText="Boş bırakılırsa rastgele şifre atanır" />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setCreateOpen(false)}>İptal</Button>
          <Button variant="contained" onClick={handleCreate}
            disabled={creating || !createName.trim()}
            startIcon={creating ? <CircularProgress size={14} color="inherit" /> : null}>
            Oluştur
          </Button>
        </DialogActions>
      </Dialog>

      <Dialog open={!!deleteTarget} onClose={() => setDeleteTarget(null)}>
        <DialogTitle>Şirketi Sil</DialogTitle>
        <DialogContent>
          <Typography><b>{deleteTarget?.name}</b> şirketini silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.</Typography>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setDeleteTarget(null)}>İptal</Button>
          <Button variant="contained" color="error" onClick={handleDelete} disabled={deleting}
            startIcon={deleting ? <CircularProgress size={14} color="inherit" /> : null}>Sil</Button>
        </DialogActions>
      </Dialog>
    </>
  );
}

export default SuperAdminCompanies;
"""

os.makedirs(os.path.dirname(sys.argv[1]), exist_ok=True)
with open(sys.argv[1], 'w') as f:
    f.write(content)
print(f"  ✓ {sys.argv[1]}")
PYEOF

# ── CompanyDetail.tsx ─────────────────────────────────────────────────────────
python3 - "$FE/src/content/own/SuperAdmin/CompanyDetail.tsx" << 'PYEOF'
import sys, os

path = sys.argv[1]
os.makedirs(os.path.dirname(path), exist_ok=True)

content = r"""import {
  Alert, Box, Button, Card, CardContent, Chip, CircularProgress, Container,
  Dialog, DialogActions, DialogContent, DialogTitle, FormControl, IconButton,
  InputLabel, MenuItem, Select, Switch, Table, TableBody, TableCell, TableHead,
  TableRow, TextField, Tooltip, Typography
} from '@mui/material';
import ArrowBackIcon from '@mui/icons-material/ArrowBack';
import DeleteIcon from '@mui/icons-material/Delete';
import EditIcon from '@mui/icons-material/Edit';
import PersonAddIcon from '@mui/icons-material/PersonAdd';
import { useEffect, useState } from 'react';
import { Helmet } from 'react-helmet-async';
import { useNavigate, useParams } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import PageTitleWrapper from 'src/components/PageTitleWrapper';
import api from 'src/utils/api';
import useAuth from 'src/hooks/useAuth';

interface SuperAdminUserDTO {
  id: number; username: string; email: string;
  firstName: string; lastName: string;
  role: { id: number; name: string; code: string } | string;
}
interface CompanyRole { id: number; name: string; roleType: string; }
interface SubscriptionPlan { id: number; name: string; code: string; }
interface SuperAdminCompanyDetailDTO {
  id: number; name: string; email: string; createdAt: string;
  subscriptionPlanId: number | null; subscriptionPlanName: string | null;
  usersLimit: number; userCount: number; expiryDate: string | null;
  users: SuperAdminUserDTO[];
}
interface FeatureStatus { feature: string; inPlan: boolean; override: boolean | null; effective: boolean; }

function SuperAdminCompanyDetail() {
  const { t } = useTranslation();
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { loginInternal } = useAuth();
  const [company, setCompany] = useState<SuperAdminCompanyDetailDTO | null>(null);
  const [loading, setLoading] = useState(true);
  const [switchingUserId, setSwitchingUserId] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [plans, setPlans] = useState<SubscriptionPlan[]>([]);
  const [selectedPlanId, setSelectedPlanId] = useState<number | ''>('');
  const [usersLimit, setUsersLimit] = useState<number>(1);
  const [savingPlan, setSavingPlan] = useState(false);
  const [planSuccess, setPlanSuccess] = useState(false);
  const [expiryDate, setExpiryDate] = useState<string>('');
  const [savingExpiry, setSavingExpiry] = useState(false);
  const [expirySuccess, setExpirySuccess] = useState(false);
  const [features, setFeatures] = useState<FeatureStatus[]>([]);
  const [savingFeature, setSavingFeature] = useState<string | null>(null);
  const [editInfoOpen, setEditInfoOpen] = useState(false);
  const [editName, setEditName] = useState('');
  const [editEmail, setEditEmail] = useState('');
  const [savingInfo, setSavingInfo] = useState(false);
  const [deleteCompanyOpen, setDeleteCompanyOpen] = useState(false);
  const [deletingCompany, setDeletingCompany] = useState(false);
  const [roles, setRoles] = useState<CompanyRole[]>([]);
  const [addUserOpen, setAddUserOpen] = useState(false);
  const [newUserEmail, setNewUserEmail] = useState('');
  const [newUserFirstName, setNewUserFirstName] = useState('');
  const [newUserLastName, setNewUserLastName] = useState('');
  const [newUserRoleId, setNewUserRoleId] = useState<number | ''>('');
  const [newUserPassword, setNewUserPassword] = useState('');
  const [addingUser, setAddingUser] = useState(false);
  const [deleteUserId, setDeleteUserId] = useState<number | null>(null);
  const [deletingUser, setDeletingUser] = useState(false);
  const [changePasswordUserId, setChangePasswordUserId] = useState<number | null>(null);
  const [newPassword, setNewPassword] = useState('');
  const [savingPassword, setSavingPassword] = useState(false);
  const [changeRoleUserId, setChangeRoleUserId] = useState<number | null>(null);
  const [changeRoleValue, setChangeRoleValue] = useState<number | ''>('');
  const [savingRole, setSavingRole] = useState(false);

  const handleSaveExpiry = async () => {
    if (!id) return;
    setSavingExpiry(true); setExpirySuccess(false); setError(null);
    try {
      await api.patch(`superadmin/companies/${id}/expiry`, {
        expiryDate: expiryDate ? new Date(expiryDate).toISOString() : null
      });
      setExpirySuccess(true);
    } catch { setError('Bitiş tarihi güncellenemedi'); }
    finally { setSavingExpiry(false); }
  };

  const loadFeatures = () => {
    if (id) {
      api.get<FeatureStatus[]>(`superadmin/companies/${id}/features`).then(setFeatures).catch(() => {});
    }
  };

  useEffect(() => {
    if (id) {
      api.get<SuperAdminCompanyDetailDTO>(`superadmin/companies/${id}`)
        .then((data) => {
          setCompany(data);
          if (data.subscriptionPlanId) setSelectedPlanId(data.subscriptionPlanId);
          if (data.usersLimit) setUsersLimit(data.usersLimit);
          if (data.expiryDate) setExpiryDate(data.expiryDate.slice(0, 10));
        })
        .catch(() => setError(t('error_loading_data')))
        .finally(() => setLoading(false));
    }
    api.get<SubscriptionPlan[]>('superadmin/subscription-plans').then(setPlans).catch(() => {});
    loadFeatures();
    if (id) {
      api.get<CompanyRole[]>(`superadmin/companies/${id}/roles`).then(setRoles).catch(() => {});
    }
  }, [id]);

  const handleFeatureOverride = async (feature: string, enabled: boolean | null) => {
    if (!id) return;
    setSavingFeature(feature);
    try {
      await api.patch(`superadmin/companies/${id}/features`, { feature, enabled });
      setFeatures((prev) =>
        prev.map((f) => f.feature === feature
          ? { ...f, override: enabled, effective: enabled !== null ? enabled : f.inPlan }
          : f)
      );
    } catch { setError('Özellik güncellenemedi'); }
    finally { setSavingFeature(null); }
  };

  const handleSavePlan = async () => {
    if (!id || selectedPlanId === '') return;
    setSavingPlan(true); setPlanSuccess(false); setError(null);
    try {
      await api.patch(`superadmin/companies/${id}/plan`, { planId: selectedPlanId, usersLimit });
      setPlanSuccess(true);
      setCompany((prev) => prev ? {
        ...prev, subscriptionPlanId: selectedPlanId as number,
        subscriptionPlanName: plans.find((p) => p.id === selectedPlanId)?.name ?? prev.subscriptionPlanName,
        usersLimit
      } : prev);
    } catch { setError('Plan güncellenemedi'); }
    finally { setSavingPlan(false); }
  };

  const handleSaveInfo = async () => {
    if (!id) return;
    setSavingInfo(true); setError(null);
    try {
      await api.patch(`superadmin/companies/${id}/info`, { name: editName, email: editEmail });
      setCompany((prev) => prev ? { ...prev, name: editName, email: editEmail } : prev);
      setEditInfoOpen(false);
    } catch { setError('Şirket bilgileri güncellenemedi'); }
    finally { setSavingInfo(false); }
  };

  const handleDeleteCompany = async () => {
    if (!id) return;
    setDeletingCompany(true);
    try {
      await api.deletes(`superadmin/companies/${id}`);
      navigate('/app/superadmin/companies');
    } catch { setError('Şirket silinemedi'); setDeletingCompany(false); setDeleteCompanyOpen(false); }
  };

  const handleAddUser = async () => {
    if (!id || !newUserEmail || newUserRoleId === '') return;
    setAddingUser(true); setError(null);
    try {
      const created = await api.post<SuperAdminUserDTO>(`superadmin/companies/${id}/users`, {
        email: newUserEmail, firstName: newUserFirstName, lastName: newUserLastName,
        roleId: newUserRoleId, password: newUserPassword || undefined
      });
      setCompany((prev) => prev
        ? { ...prev, users: [...(prev.users || []), created], userCount: prev.userCount + 1 }
        : prev);
      setAddUserOpen(false);
      setNewUserEmail(''); setNewUserFirstName(''); setNewUserLastName('');
      setNewUserRoleId(''); setNewUserPassword('');
    } catch { setError('Kullanıcı eklenemedi. E-posta zaten kullanımda olabilir.'); }
    finally { setAddingUser(false); }
  };

  const handleDeleteUser = async () => {
    if (!id || deleteUserId === null) return;
    setDeletingUser(true);
    try {
      await api.deletes(`superadmin/companies/${id}/users/${deleteUserId}`);
      setCompany((prev) => prev
        ? { ...prev, users: prev.users.filter((u) => u.id !== deleteUserId), userCount: prev.userCount - 1 }
        : prev);
      setDeleteUserId(null);
    } catch { setError('Kullanıcı silinemedi'); }
    finally { setDeletingUser(false); }
  };

  const handleChangeRole = async () => {
    if (!id || changeRoleUserId === null || changeRoleValue === '') return;
    setSavingRole(true);
    try {
      await api.patch(`superadmin/companies/${id}/users/${changeRoleUserId}/role`, { roleId: changeRoleValue });
      const roleName = roles.find((r) => r.id === changeRoleValue)?.name ?? '';
      setCompany((prev) => prev
        ? { ...prev, users: prev.users.map((u) => u.id === changeRoleUserId ? { ...u, role: roleName } : u) }
        : prev);
      setChangeRoleUserId(null); setChangeRoleValue('');
    } catch { setError('Rol değiştirilemedi'); }
    finally { setSavingRole(false); }
  };

  const handleChangePassword = async () => {
    if (!id || changePasswordUserId === null || !newPassword) return;
    setSavingPassword(true); setError(null);
    try {
      await api.patch(`superadmin/companies/${id}/users/${changePasswordUserId}/password`, { newPassword });
      setChangePasswordUserId(null); setNewPassword('');
    } catch { setError('Şifre değiştirilemedi'); }
    finally { setSavingPassword(false); }
  };

  const handleSwitchUser = async (userId: number) => {
    setSwitchingUserId(userId); setError(null);
    try {
      const currentToken = window.localStorage.getItem('accessToken');
      if (currentToken) window.localStorage.setItem('superadminToken', currentToken);
      const response = await api.post<{ accessToken: string }>(`superadmin/switch/${userId}`, {});
      await loginInternal(response.accessToken);
      navigate('/app/work-orders');
    } catch { setError(t('switch_user_failed')); }
    finally { setSwitchingUserId(null); }
  };

  const handleReturnToSuperAdmin = async () => {
    const superadminToken = window.localStorage.getItem('superadminToken');
    if (superadminToken) {
      window.localStorage.removeItem('superadminToken');
      await loginInternal(superadminToken);
      navigate('/app/superadmin/companies');
    }
  };

  return (
    <>
      <Helmet><title>Superadmin - {company?.name ?? t('company_details')}</title></Helmet>
      {localStorage.getItem('superadminToken') && (
        <Box display="flex" justifyContent="flex-end" p={1}>
          <Button variant="contained" color="warning" onClick={handleReturnToSuperAdmin}>
            ← Superadmin'e Dön
          </Button>
        </Box>
      )}
      <PageTitleWrapper>
        <Box display="flex" justifyContent="space-between" alignItems="flex-start" width="100%">
          <Box>
            <Button startIcon={<ArrowBackIcon />} onClick={() => navigate('/app/superadmin/companies')} sx={{ mb: 1 }}>
              {t('companies')}
            </Button>
            <Typography variant="h2">{company?.name ?? t('company_details')}</Typography>
          </Box>
          {company && (
            <Box display="flex" gap={1} mt={1}>
              <Button variant="outlined" startIcon={<EditIcon />}
                onClick={() => { setEditName(company.name); setEditEmail(company.email ?? ''); setEditInfoOpen(true); }}>
                Düzenle
              </Button>
              <Button variant="outlined" color="error" startIcon={<DeleteIcon />}
                onClick={() => setDeleteCompanyOpen(true)}>Şirketi Sil</Button>
            </Box>
          )}
        </Box>
      </PageTitleWrapper>

      <Container maxWidth="lg">
        {error && <Alert severity="error" sx={{ mb: 2 }}>{error}</Alert>}
        {loading ? (
          <Box display="flex" justifyContent="center" p={4}><CircularProgress /></Box>
        ) : !company ? (
          <Typography>{t('company_not_found')}</Typography>
        ) : (
          <Box display="flex" flexDirection="column" gap={3}>
            <Card>
              <CardContent>
                <Typography variant="h4" gutterBottom>{t('company_details')}</Typography>
                <Box display="flex" gap={4} flexWrap="wrap" mb={3}>
                  <Box>
                    <Typography variant="caption" color="text.secondary">{t('email')}</Typography>
                    <Typography>{company.email || '-'}</Typography>
                  </Box>
                  <Box>
                    <Typography variant="caption" color="text.secondary">{t('subscription_plan')}</Typography>
                    <Typography>
                      {company.subscriptionPlanName
                        ? <Chip label={company.subscriptionPlanName} size="small" color="primary" variant="outlined" />
                        : '-'}
                    </Typography>
                  </Box>
                  <Box>
                    <Typography variant="caption" color="text.secondary">{t('user_count')}</Typography>
                    <Typography>{company.userCount}</Typography>
                  </Box>
                  <Box>
                    <Typography variant="caption" color="text.secondary">Kullanıcı Limiti</Typography>
                    <Typography>{company.usersLimit || '-'}</Typography>
                  </Box>
                </Box>

                <Typography variant="h6" gutterBottom>Plan Güncelle</Typography>
                {planSuccess && <Alert severity="success" sx={{ mb: 2 }}>Plan başarıyla güncellendi.</Alert>}
                <Box display="flex" gap={2} alignItems="flex-end" flexWrap="wrap">
                  <FormControl size="small" sx={{ minWidth: 200 }}>
                    <InputLabel>Plan</InputLabel>
                    <Select value={selectedPlanId} label="Plan"
                      onChange={(e) => setSelectedPlanId(e.target.value as number)}>
                      {plans.map((plan) => <MenuItem key={plan.id} value={plan.id}>{plan.name}</MenuItem>)}
                    </Select>
                  </FormControl>
                  <TextField size="small" label="Kullanıcı Limiti" type="number" value={usersLimit}
                    onChange={(e) => setUsersLimit(Math.max(1, parseInt(e.target.value, 10) || 1))}
                    inputProps={{ min: 1 }} sx={{ width: 160 }} />
                  <Button variant="contained" onClick={handleSavePlan}
                    disabled={savingPlan || selectedPlanId === ''}
                    startIcon={savingPlan ? <CircularProgress size={14} color="inherit" /> : null}>Kaydet</Button>
                </Box>

                <Typography variant="h6" gutterBottom sx={{ mt: 3 }}>Abonelik Bitiş Tarihi</Typography>
                <Typography variant="body2" color="text.secondary" sx={{ mb: 1 }}>
                  Bu tarihten sonra şirket kullanıcıları giriş yapamaz. Boş bırakılırsa kısıtlama olmaz.
                </Typography>
                {expirySuccess && <Alert severity="success" sx={{ mb: 2 }}>Bitiş tarihi güncellendi.</Alert>}
                <Box display="flex" gap={2} alignItems="flex-end" flexWrap="wrap">
                  <TextField size="small" label="Bitiş Tarihi" type="date" value={expiryDate}
                    onChange={(e) => setExpiryDate(e.target.value)}
                    InputLabelProps={{ shrink: true }} sx={{ width: 200 }} />
                  <Button variant="contained" color="warning" onClick={handleSaveExpiry} disabled={savingExpiry}
                    startIcon={savingExpiry ? <CircularProgress size={14} color="inherit" /> : null}>Kaydet</Button>
                  {expiryDate && (
                    <Button variant="outlined" color="inherit" disabled={savingExpiry}
                      onClick={() => { setExpiryDate(''); api.patch(`superadmin/companies/${id}/expiry`, { expiryDate: null }).catch(() => {}); }}>
                      Tarihi Kaldır
                    </Button>
                  )}
                </Box>
              </CardContent>
            </Card>

            <Card>
              <CardContent>
                <Box display="flex" justifyContent="space-between" alignItems="center" mb={2}>
                  <Typography variant="h4">{t('users')} ({company.userCount})</Typography>
                  <Button variant="outlined" size="small" startIcon={<PersonAddIcon />}
                    onClick={() => setAddUserOpen(true)}>Kullanıcı Ekle</Button>
                </Box>
                {!company.users || company.users.length === 0 ? (
                  <Typography color="text.secondary">{t('no_users')}</Typography>
                ) : (
                  <Table>
                    <TableHead>
                      <TableRow>
                        <TableCell><b>{t('name')}</b></TableCell>
                        <TableCell><b>{t('email')}</b></TableCell>
                        <TableCell><b>{t('role')}</b></TableCell>
                        <TableCell />
                      </TableRow>
                    </TableHead>
                    <TableBody>
                      {company.users.map((user) => {
                        const roleName = typeof user.role === 'string'
                          ? user.role
                          : (user.role as any)?.name ?? (user.role as any)?.code ?? '-';
                        return (
                          <TableRow key={user.id} hover>
                            <TableCell>
                              {user.firstName || user.lastName
                                ? `${user.firstName ?? ''} ${user.lastName ?? ''}`.trim()
                                : (user as any).username ?? '-'}
                            </TableCell>
                            <TableCell>{user.email}</TableCell>
                            <TableCell>
                              {changeRoleUserId === user.id ? (
                                <Box display="flex" gap={1} alignItems="center">
                                  <Select size="small" value={changeRoleValue}
                                    onChange={(e) => setChangeRoleValue(e.target.value as number)}
                                    sx={{ minWidth: 140 }}>
                                    {roles.map((r) => <MenuItem key={r.id} value={r.id}>{r.name}</MenuItem>)}
                                  </Select>
                                  <Button size="small" variant="contained"
                                    disabled={savingRole || changeRoleValue === ''} onClick={handleChangeRole}>
                                    {savingRole ? <CircularProgress size={14} /> : 'Kaydet'}
                                  </Button>
                                  <Button size="small" onClick={() => setChangeRoleUserId(null)}>İptal</Button>
                                </Box>
                              ) : (
                                <Chip label={roleName} size="small" variant="outlined"
                                  onClick={() => { setChangeRoleUserId(user.id); setChangeRoleValue(''); }} />
                              )}
                            </TableCell>
                            <TableCell>
                              <Box display="flex" gap={1}>
                                <Button variant="outlined" size="small"
                                  onClick={() => navigate(`/app/superadmin/user-features/${user.id}`)}>
                                  Özellikler
                                </Button>
                                <Button variant="contained" size="small" disabled={switchingUserId !== null}
                                  startIcon={switchingUserId === user.id ? <CircularProgress size={14} color="inherit" /> : null}
                                  onClick={() => handleSwitchUser(user.id)}>
                                  {t('switch_to_user')}
                                </Button>
                                <Button variant="outlined" size="small"
                                  onClick={() => { setChangePasswordUserId(user.id); setNewPassword(''); }}>
                                  Şifre
                                </Button>
                                <IconButton size="small" color="error" onClick={() => setDeleteUserId(user.id)}>
                                  <DeleteIcon fontSize="small" />
                                </IconButton>
                              </Box>
                            </TableCell>
                          </TableRow>
                        );
                      })}
                    </TableBody>
                  </Table>
                )}
              </CardContent>
            </Card>

            {features.length > 0 && (
              <Card>
                <CardContent>
                  <Typography variant="h4" gutterBottom>Özellik Override'ları</Typography>
                  <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
                    Toggle: aktif/pasif override. "Planı Kullan" ile override'ı sil.
                  </Typography>
                  <Table size="small">
                    <TableHead>
                      <TableRow>
                        <TableCell><b>Özellik</b></TableCell>
                        <TableCell align="center"><b>Planda Var mı?</b></TableCell>
                        <TableCell align="center"><b>Override</b></TableCell>
                        <TableCell align="center"><b>Aktif</b></TableCell>
                        <TableCell align="center"><b>İşlem</b></TableCell>
                      </TableRow>
                    </TableHead>
                    <TableBody>
                      {features.map((f) => (
                        <TableRow key={f.feature} hover>
                          <TableCell><Typography variant="body2" fontFamily="monospace">{f.feature}</Typography></TableCell>
                          <TableCell align="center">
                            <Chip label={f.inPlan ? 'Evet' : 'Hayır'} size="small"
                              color={f.inPlan ? 'success' : 'default'} variant="outlined" />
                          </TableCell>
                          <TableCell align="center">
                            {f.override !== null
                              ? <Chip label={f.override ? 'Açık' : 'Kapalı'} size="small" color={f.override ? 'primary' : 'error'} />
                              : <Typography variant="caption" color="text.secondary">—</Typography>}
                          </TableCell>
                          <TableCell align="center">
                            {savingFeature === f.feature ? <CircularProgress size={20} /> : (
                              <Tooltip title={f.effective ? 'Aktif' : 'Pasif'}>
                                <Switch checked={f.effective} size="small"
                                  onChange={(e) => handleFeatureOverride(f.feature, e.target.checked)} />
                              </Tooltip>
                            )}
                          </TableCell>
                          <TableCell align="center">
                            {f.override !== null && (
                              <Button size="small" variant="outlined" color="inherit"
                                disabled={savingFeature === f.feature}
                                onClick={() => handleFeatureOverride(f.feature, null)}>Planı Kullan</Button>
                            )}
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </CardContent>
              </Card>
            )}
          </Box>
        )}
      </Container>

      {/* Edit company info */}
      <Dialog open={editInfoOpen} onClose={() => setEditInfoOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>Şirket Bilgilerini Düzenle</DialogTitle>
        <DialogContent>
          <TextField label="Şirket Adı" fullWidth margin="normal" autoFocus value={editName}
            onChange={(e) => setEditName(e.target.value)} />
          <TextField label="E-posta" fullWidth margin="normal" type="email" value={editEmail}
            onChange={(e) => setEditEmail(e.target.value)} />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setEditInfoOpen(false)}>İptal</Button>
          <Button variant="contained" onClick={handleSaveInfo} disabled={savingInfo || !editName.trim()}
            startIcon={savingInfo ? <CircularProgress size={14} color="inherit" /> : null}>Kaydet</Button>
        </DialogActions>
      </Dialog>

      {/* Delete company */}
      <Dialog open={deleteCompanyOpen} onClose={() => setDeleteCompanyOpen(false)}>
        <DialogTitle>Şirketi Sil</DialogTitle>
        <DialogContent>
          <Typography><b>{company?.name}</b> şirketini ve tüm verilerini silmek istediğinizden emin misiniz? Geri alınamaz.</Typography>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setDeleteCompanyOpen(false)}>İptal</Button>
          <Button variant="contained" color="error" onClick={handleDeleteCompany} disabled={deletingCompany}
            startIcon={deletingCompany ? <CircularProgress size={14} color="inherit" /> : null}>Sil</Button>
        </DialogActions>
      </Dialog>

      {/* Add user */}
      <Dialog open={addUserOpen} onClose={() => setAddUserOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>Kullanıcı Ekle</DialogTitle>
        <DialogContent>
          <TextField label="E-posta *" fullWidth margin="normal" type="email" autoFocus value={newUserEmail}
            onChange={(e) => setNewUserEmail(e.target.value)} />
          <TextField label="Ad" fullWidth margin="normal" value={newUserFirstName}
            onChange={(e) => setNewUserFirstName(e.target.value)} />
          <TextField label="Soyad" fullWidth margin="normal" value={newUserLastName}
            onChange={(e) => setNewUserLastName(e.target.value)} />
          <FormControl fullWidth margin="normal">
            <InputLabel>Rol *</InputLabel>
            <Select value={newUserRoleId} label="Rol *"
              onChange={(e) => setNewUserRoleId(e.target.value as number)}>
              {roles.map((r) => <MenuItem key={r.id} value={r.id}>{r.name}</MenuItem>)}
            </Select>
          </FormControl>
          <TextField label="Şifre" fullWidth margin="normal" type="password" value={newUserPassword}
            onChange={(e) => setNewUserPassword(e.target.value)}
            helperText="Boş bırakılırsa rastgele şifre atanır." />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setAddUserOpen(false)}>İptal</Button>
          <Button variant="contained" onClick={handleAddUser}
            disabled={addingUser || !newUserEmail || newUserRoleId === ''}
            startIcon={addingUser ? <CircularProgress size={14} color="inherit" /> : null}>Ekle</Button>
        </DialogActions>
      </Dialog>

      {/* Change password */}
      <Dialog open={changePasswordUserId !== null} onClose={() => setChangePasswordUserId(null)} maxWidth="xs" fullWidth>
        <DialogTitle>Şifre Değiştir</DialogTitle>
        <DialogContent>
          <TextField label="Yeni Şifre *" fullWidth margin="normal" type="password" autoFocus value={newPassword}
            onChange={(e) => setNewPassword(e.target.value)} />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setChangePasswordUserId(null)}>İptal</Button>
          <Button variant="contained" onClick={handleChangePassword} disabled={savingPassword || !newPassword}
            startIcon={savingPassword ? <CircularProgress size={14} color="inherit" /> : null}>Kaydet</Button>
        </DialogActions>
      </Dialog>

      {/* Delete user */}
      <Dialog open={deleteUserId !== null} onClose={() => setDeleteUserId(null)}>
        <DialogTitle>Kullanıcıyı Sil</DialogTitle>
        <DialogContent>
          <Typography>Bu kullanıcıyı şirketten silmek istediğinizden emin misiniz?</Typography>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setDeleteUserId(null)}>İptal</Button>
          <Button variant="contained" color="error" onClick={handleDeleteUser} disabled={deletingUser}
            startIcon={deletingUser ? <CircularProgress size={14} color="inherit" /> : null}>Sil</Button>
        </DialogActions>
      </Dialog>
    </>
  );
}

export default SuperAdminCompanyDetail;
"""

with open(path, 'w') as f:
    f.write(content)
print(f"  ✓ {path}")
PYEOF

ok "SuperAdmin sayfaları tamamlandı"

# ════════════════════════════════════════════════════════════════════════════
# BÖLÜM 7 – Frontend: router ve i18n güncelle
# ════════════════════════════════════════════════════════════════════════════
hdr "7/8  Frontend – router/app.tsx ve tr.ts güncelle"

# ── router/app.tsx ──────────────────────────────────────────────────────────
python3 - "$FE/src/router/app.tsx" << 'PYEOF'
import sys, re

path = sys.argv[1]
with open(path) as f:
    src = f.read()

changed = False

# 1) SuperAdmin import'larını ekle (lazy import'lar)
imports_to_add = """
import UserFeatureManagement from 'src/components/SuperAdmin/UserFeatureManagement';
const SuperAdminCompanies = Loader(
  lazy(() => import('../content/own/SuperAdmin/Companies'))
);
const SuperAdminCompanyDetail = Loader(
  lazy(() => import('../content/own/SuperAdmin/CompanyDetail'))
);

const UserFeatureManagementWrapper = () => {
  const { userId } = useParams();
  return <UserFeatureManagement userId={Number(userId)} />;
};
"""

if 'SuperAdminCompanies' not in src:
    # useParams import'u ekle
    src = src.replace(
        "import { lazy, Suspense } from 'react';",
        "import { lazy, Suspense } from 'react';\nimport { useParams } from 'react-router-dom';"
    )
    # Son import'tan sonra ekle (SuspenseLoader'dan sonra)
    src = src.replace(
        "import SuspenseLoader from 'src/components/SuspenseLoader';",
        "import SuspenseLoader from 'src/components/SuspenseLoader';" + imports_to_add
    )
    changed = True
    print("  ✓ SuperAdmin import'ları eklendi")
else:
    print("  [SKIP] SuperAdmin import'ları zaten mevcut")

# 2) Route tanımlarını ekle
superadmin_routes = """
  {
    path: 'superadmin',
    children: [
      { path: 'companies', element: <SuperAdminCompanies /> },
      { path: 'companies/:id', element: <SuperAdminCompanyDetail /> },
      { path: 'user-features/:userId', element: <UserFeatureManagementWrapper /> }
    ]
  }
"""

if 'superadmin' not in src:
    # appRoutes dizisinin kapanışından önce ekle
    src = re.sub(
        r'(\];\s*\nexport default appRoutes;)',
        ',' + superadmin_routes + r'\n];\nexport default appRoutes;',
        src,
        count=1
    )
    # Alternatif: son eleman sonrasına ekle
    if 'superadmin' not in src:
        src = src.replace(
            '];',
            ',' + superadmin_routes + '\n];',
            1  # sadece ilk kez
        )
    changed = True
    print("  ✓ Superadmin route'ları eklendi")
else:
    print("  [SKIP] Superadmin route'ları zaten mevcut")

if changed:
    with open(path, 'w') as f:
        f.write(src)
PYEOF

# ── tr.ts ───────────────────────────────────────────────────────────────────
python3 - "$FE/src/i18n/translations/tr.ts" << 'PYEOF'
import sys

path = sys.argv[1]
with open(path) as f:
    src = f.read()

new_keys = {
    'companies': 'Şirketler',
    'subscription_plan': 'Abonelik Planı',
    'user_count': 'Kullanıcı Sayısı',
    'switch_to_user': 'Kullanıcıya Geç',
    'no_companies': 'Şirket bulunamadı',
    'company_not_found': 'Şirket bulunamadı',
    'no_users': 'Kullanıcı bulunamadı',
    'switch_user_failed': 'Kullanıcıya geçiş başarısız',
    'Superadmin': 'Superadmin',
    'superadmin_panel': 'Superadmin Paneli',
}

added = []
for key, value in new_keys.items():
    # tr.ts içinde anahtar tırnaksız yazılıyor: "  companies:"
    if f"  {key}:" in src or f"'{key}'" in src or f'"{key}"' in src:
        continue
    # Kapanış parantezinden önce ekle
    src = src.replace(
        '};',
        f"  {key}: '{value}',\n}};",
        1
    )
    added.append(key)

if added:
    with open(path, 'w') as f:
        f.write(src)
    print(f"  ✓ tr.ts'e eklenen anahtarlar: {', '.join(added)}")
else:
    print("  [SKIP] tr.ts zaten güncel")
PYEOF

ok "router ve i18n güncellendi"

# ════════════════════════════════════════════════════════════════════════════
# BÖLÜM 8 – CompanyDetail.tsx (embedded içerik)
# ════════════════════════════════════════════════════════════════════════════
# (Zaten TARGET içinde olduğu için sadece varlık kontrolü yapılıyor)
hdr "8/8  Kontrol & Özet"

MISSING=()
check_file() {
    if [[ ! -f "$1" ]]; then MISSING+=("$1"); echo "  ✗ EKSIK: $1"
    else echo "  ✓ $1"; fi
}

check_file "$API/src/main/java/com/grash/service/LicenseService.java"
check_file "$API/src/main/java/com/grash/controller/SuperAdminController.java"
check_file "$API/src/main/java/com/grash/controller/UserFeatureController.java"
check_file "$API/src/main/java/com/grash/model/CompanyFeatureOverride.java"
check_file "$API/src/main/java/com/grash/model/Feature.java"
check_file "$API/src/main/java/com/grash/model/UserFeaturePermission.java"
check_file "$API/src/main/java/com/grash/repository/CompanyFeatureOverrideRepository.java"
check_file "$API/src/main/java/com/grash/repository/FeatureRepository.java"
check_file "$API/src/main/java/com/grash/repository/UserFeaturePermissionRepository.java"
check_file "$CHANGELOG/2026_04_05_1744000000_company_feature_overrides.xml"
check_file "$CHANGELOG/2026_04_05_1744000001_subscription_expiry_date.xml"
check_file "$CHANGELOG/2026_04_09_0001_create_features_table.xml"
check_file "$CHANGELOG/2026_04_09_0002_create_user_feature_permissions.xml"
check_file "$FE/src/content/own/SuperAdmin/Companies.tsx"
check_file "$FE/src/content/own/SuperAdmin/CompanyDetail.tsx"
check_file "$FE/src/components/SuperAdmin/UserFeatureManagement.tsx"
check_file "$FE/src/hooks/useLicenseEntitlement.ts"

# ════════════════════════════════════════════════════════════════════════════
# Docker Compose
# ════════════════════════════════════════════════════════════════════════════
echo ""
if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "⚠  ${#MISSING[@]} dosya eksik. Lütfen yukarıdaki listeyi kontrol edin."
fi

if [[ "$START_DOCKER" == "true" ]]; then
    if [[ -f "$TARGET/docker-compose.yml" ]]; then
        echo "▶ docker-compose up -d başlatılıyor..."
        cd "$TARGET"
        docker-compose up -d
        echo "✅ Servisler başlatıldı."
    else
        echo "⚠  $TARGET/docker-compose.yml bulunamadı — docker-compose atlandı."
        echo "   Manuel başlatmak için: cd $TARGET && docker-compose up -d"
    fi
else
    echo "ℹ  Docker başlatma atlandı (--no-docker)."
fi

echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  Setup tamamlandı!"
echo "  Superadmin panel: /app/superadmin/companies"
echo "  Endpointler     : /superadmin/** (ROLE_SUPER_ADMIN gerekli)"
echo "══════════════════════════════════════════════════════════════"
