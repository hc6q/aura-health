import Foundation

enum AITools {
    // MARK: - Tool Definitions

    private static let toolSchemas: [[String: Any]] = [
        // READ tools
        [
            "name": "get_vitals",
            "description": "Get recent vital measurements. Use when user asks about weight, heart rate, sleep, steps, etc.",
            "parameters": [
                "type": "object",
                "properties": [
                    "metric": [
                        "type": "string",
                        "enum": ["weight", "heartRate", "sleepDuration", "sleepScore", "steps", "activeMinutes", "hrv", "recovery", "strain", "spo2", "skinTemp", "calories", "bloodPressure"],
                        "description": "Filter by metric type. Omit for all."
                    ],
                    "days": [
                        "type": "integer",
                        "description": "Days to look back (1-90). Default 7."
                    ]
                ],
                "required": [] as [String]
            ]
        ],
        [
            "name": "get_biomarkers",
            "description": "Get lab biomarker results. Use when user asks about blood work, lab results, or specific markers like cholesterol, TSH, ApoB, Apolipoprotein B, glucose, etc. Always call this for any lab/blood test question.",
            "parameters": [
                "type": "object",
                "properties": [
                    "marker": [
                        "type": "string",
                        "description": "Filter by marker name (e.g. 'Hemoglobin', 'TSH', 'cholesterol'). Strongly recommended to filter."
                    ],
                    "system": [
                        "type": "string",
                        "enum": ["Heart", "Metabolic", "Liver", "Kidney", "Thyroid", "Blood", "Hormones", "Inflammation", "Vitamins"],
                        "description": "Filter by body system. Use instead of marker for broader queries."
                    ]
                ],
                "required": [] as [String]
            ]
        ],
        [
            "name": "get_medications",
            "description": "Get active medications list.",
            "parameters": [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ],
        [
            "name": "get_conditions",
            "description": "Get health conditions list.",
            "parameters": [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ],
        [
            "name": "get_habits",
            "description": "Get habits list with recent completion status.",
            "parameters": [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ],
        [
            "name": "get_diet",
            "description": "Get the current active diet plan with approved and avoided food categories.",
            "parameters": [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ],
        [
            "name": "get_health_summary",
            "description": "Get a comprehensive health overview — latest vitals, active conditions, medications, habits, and recent biomarkers. Use when user asks for an overview, summary, or 'how am I doing'.",
            "parameters": [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ],
        [
            "name": "import_lab_results",
            "description": "Import biomarkers from an attached lab report file (PDF or image). ONLY use when the user attaches a file and asks to import lab results. The file is already attached to the conversation — just call this tool.",
            "parameters": [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ],
        // WRITE tools
        [
            "name": "add_biomarker",
            "description": "Add a lab result. ONLY use when user explicitly asks to add/record a biomarker value.",
            "parameters": [
                "type": "object",
                "properties": [
                    "marker": ["type": "string", "description": "Standardized marker name (e.g. 'Total Cholesterol', 'TSH', 'Hemoglobin')"],
                    "value": ["type": "number", "description": "The numeric value"],
                    "unit": ["type": "string", "description": "Unit of measurement (e.g. 'mg/dL', 'mIU/L')"],
                    "refMin": ["type": "number", "description": "Reference range minimum (if known)"],
                    "refMax": ["type": "number", "description": "Reference range maximum (if known)"],
                    "lab": ["type": "string", "description": "Lab name (if mentioned, e.g. 'Quest', 'LabCorp')"],
                    "testDate": ["type": "string", "description": "Test date as YYYY-MM-DD. Use today if not specified."]
                ],
                "required": ["marker", "value", "unit"]
            ]
        ],
        [
            "name": "add_measurement",
            "description": "Log a vital measurement. ONLY use when user explicitly asks to log/record a measurement. Note: sleepScore, recovery, strain, skinTemp are read-only sensor metrics and cannot be logged manually. For weight: always pass the unit the user specified (lbs or kg). If the user says a number without a unit, use their preferred unit from the system prompt.",
            "parameters": [
                "type": "object",
                "properties": [
                    "metric": [
                        "type": "string",
                        "enum": ["weight", "heartRate", "sleepDuration", "steps", "activeMinutes", "hrv", "spo2", "calories", "bloodPressure"],
                        "description": "Metric type"
                    ],
                    "value": ["type": "number", "description": "The numeric value in the unit the user specified"],
                    "value2": ["type": "number", "description": "Second value (only for bloodPressure: diastolic)"],
                    "unit": ["type": "string", "description": "Unit for the value. For weight: 'lbs' or 'kg'. For temperature: 'F' or 'C'. If user says pounds/lbs, use 'lbs'. If user says kg/kilograms, use 'kg'."],
                    "date": ["type": "string", "description": "Date as YYYY-MM-DD. Use today if not specified."]
                ],
                "required": ["metric", "value"]
            ]
        ],
        [
            "name": "log_medication",
            "description": "Log that a medication was taken. ONLY use when user explicitly says they took a medication.",
            "parameters": [
                "type": "object",
                "properties": [
                    "medicationName": ["type": "string", "description": "Name of the medication"],
                    "date": ["type": "string", "description": "Date as YYYY-MM-DD. Use today if not specified."]
                ],
                "required": ["medicationName"]
            ]
        ],
        [
            "name": "add_habit",
            "description": "Create a new habit to track. ONLY use when user explicitly asks to add/create a habit.",
            "parameters": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "Name of the habit (e.g. 'Reading', 'Meditation', 'Cold Shower')"],
                    "category": [
                        "type": "string",
                        "enum": ["lifestyle", "therapy", "diet", "exercise"],
                        "description": "Category. Default: lifestyle."
                    ],
                    "trackingType": [
                        "type": "string",
                        "enum": ["boolean", "quantity"],
                        "description": "boolean = did/didn't do it, quantity = track a number (e.g. cups of water). Default: boolean."
                    ],
                    "unit": ["type": "string", "description": "Unit for quantity tracking (e.g. 'cups', 'minutes', 'pages'). Only needed if trackingType is quantity."],
                    "gridSection": [
                        "type": "string",
                        "enum": ["morning", "afternoon", "evening", "night"],
                        "description": "When in the day this habit is done. Default: morning."
                    ]
                ],
                "required": ["name"]
            ]
        ],
        [
            "name": "log_habit",
            "description": "Log a habit as completed for today or a given date. ONLY use when user says they did a habit.",
            "parameters": [
                "type": "object",
                "properties": [
                    "habitName": ["type": "string", "description": "Name of the habit"],
                    "completed": ["type": "boolean", "description": "Whether the habit was completed. Default: true."],
                    "quantity": ["type": "number", "description": "Quantity value (only for quantity-tracked habits)"],
                    "date": ["type": "string", "description": "Date as YYYY-MM-DD. Use today if not specified."]
                ],
                "required": ["habitName"]
            ]
        ],
        [
            "name": "add_condition",
            "description": "Add a health condition. ONLY use when user explicitly asks to add/record a condition.",
            "parameters": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "Condition name (e.g. 'Asthma', 'Type 2 Diabetes', 'Anxiety')"],
                    "status": [
                        "type": "string",
                        "enum": ["active", "managed", "resolved"],
                        "description": "Condition status. Default: active."
                    ],
                    "notes": ["type": "string", "description": "Optional notes about the condition"]
                ],
                "required": ["name"]
            ]
        ],
        [
            "name": "add_medication",
            "description": "Add a new medication to track. ONLY use when user explicitly asks to add a medication.",
            "parameters": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "Medication name"],
                    "dosage": ["type": "string", "description": "Dosage (e.g. '10mg', '500mg')"],
                    "frequency": [
                        "type": "string",
                        "enum": ["daily", "twiceDaily", "threeTimesDaily", "weekly", "asNeeded"],
                        "description": "How often. Default: daily."
                    ],
                    "type": [
                        "type": "string",
                        "enum": ["rx", "supplement", "otc"],
                        "description": "Medication type. Default: rx."
                    ],
                    "timing": [
                        "type": "string",
                        "enum": ["amFasted", "withFood", "bedtime", "anyTime"],
                        "description": "When to take it. Default: anyTime."
                    ],
                    "condition": ["type": "string", "description": "What condition this is for (optional)"]
                ],
                "required": ["name"]
            ]
        ],
        [
            "name": "deactivate_habit",
            "description": "Deactivate/stop tracking a habit. ONLY use when user asks to stop, remove, or delete a habit.",
            "parameters": [
                "type": "object",
                "properties": [
                    "habitName": ["type": "string", "description": "Name of the habit to deactivate"]
                ],
                "required": ["habitName"]
            ]
        ],
        [
            "name": "deactivate_medication",
            "description": "Deactivate/stop a medication. ONLY use when user says they stopped taking a medication.",
            "parameters": [
                "type": "object",
                "properties": [
                    "medicationName": ["type": "string", "description": "Name of the medication to deactivate"]
                ],
                "required": ["medicationName"]
            ]
        ],
        [
            "name": "update_condition",
            "description": "Update a condition's status. Use when user says a condition is now managed, resolved, etc.",
            "parameters": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "Condition name"],
                    "status": [
                        "type": "string",
                        "enum": ["active", "managed", "resolved"],
                        "description": "New status"
                    ]
                ],
                "required": ["name", "status"]
            ]
        ],
        [
            "name": "delete_measurement",
            "description": "Delete a vital measurement entry. ONLY use when user explicitly asks to delete/remove a specific measurement. Always confirm what will be deleted before calling. If multiple entries match, list them and ask which one to delete.",
            "parameters": [
                "type": "object",
                "properties": [
                    "metric": [
                        "type": "string",
                        "enum": ["weight", "heartRate", "sleepDuration", "steps", "activeMinutes", "hrv", "spo2", "calories", "bloodPressure"],
                        "description": "Metric type to delete"
                    ],
                    "date": ["type": "string", "description": "Date of the entry as YYYY-MM-DD. Required to avoid deleting the wrong entry."],
                    "value": ["type": "number", "description": "The value to match (optional, for disambiguation when multiple entries exist on the same date)"]
                ],
                "required": ["metric", "date"]
            ]
        ],
        [
            "name": "delete_biomarker",
            "description": "Delete a biomarker/lab result entry. ONLY use when user explicitly asks to delete/remove a specific biomarker. Always confirm what will be deleted before calling.",
            "parameters": [
                "type": "object",
                "properties": [
                    "marker": ["type": "string", "description": "Marker name (e.g. 'Total Cholesterol', 'TSH')"],
                    "date": ["type": "string", "description": "Test date as YYYY-MM-DD. Required to avoid deleting the wrong entry."],
                    "value": ["type": "number", "description": "The value to match (optional, for disambiguation)"]
                ],
                "required": ["marker", "date"]
            ]
        ],
        [
            "name": "navigate",
            "description": "Navigate to a specific section of the app. Use when user says 'show me', 'go to', 'open' a section.",
            "parameters": [
                "type": "object",
                "properties": [
                    "section": [
                        "type": "string",
                        "enum": ["today", "vitals", "correlations", "conditions", "medications", "biomarkers", "diet", "exercise", "vault", "settings"],
                        "description": "App section to navigate to"
                    ]
                ],
                "required": ["section"]
            ]
        ]
    ]

    /// Only schemas are dynamic; the wire protocol is Codable.
    static func definitions() throws -> [AIToolDefinition] {
        try toolSchemas.map { schema in
            let data = try JSONSerialization.data(withJSONObject: schema)
            return AIToolDefinition(function: try JSONDecoder().decode(AIToolDefinition.Function.self, from: data))
        }
    }

}
