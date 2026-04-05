package demo.users

import rego.v1

# Fallback user-department mappings
# In production, JWT claims from Keycloak are the primary source.
# Alex has both engineering and hr access.

user_departments_fallback := {
    "alex": ["engineering", "hr"],
}

has_department(user_name, department) if {
    department_list := get_departments(user_name)
    department in department_list
}

# Rule 1: Use JWT claims from direct access request
get_departments(_) := departments if {
    not input.delegation
    departments := input.user_departments
    count(departments) > 0
}

# Rule 2: Use JWT claims from delegation context
get_departments(_) := departments if {
    input.delegation
    departments := input.delegation.user_departments
    count(departments) > 0
}

# Rule 3: Use top-level user_departments even with delegation (fallback)
get_departments(_) := departments if {
    input.delegation
    not input.delegation.user_departments
    departments := input.user_departments
    count(departments) > 0
}

# Rule 4: Fallback to hardcoded mappings
get_departments(user_name) := departments if {
    not jwt_claims_provided
    departments := user_departments_fallback[user_name]
}

# Rule 5: Default for unknown users
get_departments(user_name) := [] if {
    not jwt_claims_provided
    not user_departments_fallback[user_name]
}

jwt_claims_provided if {
    input.user_departments
    count(input.user_departments) > 0
}

jwt_claims_provided if {
    input.delegation.user_departments
    count(input.delegation.user_departments) > 0
}
