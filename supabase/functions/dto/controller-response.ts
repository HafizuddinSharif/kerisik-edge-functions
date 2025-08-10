// This is a DTO for the response from the controller

interface Ingredient {
    name: string;
    quantity: number;
    unit: string;
}

interface MealContent {
    meal_name: string;
    ingredients: Ingredient[];
    instructions: string[];
    meal_description: string;
    able_to_extract: boolean;
    serving_suggestion: number;
    cooking_time: number;
}

export interface ImportFromUrlResponse {
    content: MealContent;
    metadata: Record<string, string>;
}

export interface RestResponse<T> {
    success: boolean;
    error: string | null;
    error_code: string | null;
    data: T | null;
}
