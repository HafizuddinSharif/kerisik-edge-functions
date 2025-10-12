// Utility function for calling the MS LLM API at http://127.0.0.1:8000

import {
    ImportFromUrlResponse,
    RestResponse,
} from "../dto/controller-response.ts";

// Types for the API request and response
export interface MSLLMRequest {
    prompt?: string;
    messages?: Array<{
        role: "user" | "assistant" | "system";
        content: string;
    }>;
    max_tokens?: number;
    temperature?: number;
    top_p?: number;
    [key: string]: any; // Allow additional properties
}

// export interface MSLLMExtractRecipeResponse {
//     success: boolean;
//     url: string;
//     content: ImportFromUrlResponse;
//     metadata: {
//         title: string;
//         description: string;
//     };
//     error: string | null;
// }

export interface MSLLMResponse {
    id?: string;
    object?: string;
    created?: number;
    model?: string;
    choices?: Array<{
        index: number;
        message: {
            role: string;
            content: string;
        };
        finish_reason?: string;
    }>;
    usage?: {
        prompt_tokens: number;
        completion_tokens: number;
        total_tokens: number;
    };
    error?: {
        message: string;
        type?: string;
        code?: string;
    };
}

export interface MSLLMOptions {
    baseUrl?: string;
    timeout?: number;
    headers?: Record<string, string>;
}

/**
 * Default configuration for the MS LLM API
 */
const DEFAULT_OPTIONS: MSLLMOptions = {
    baseUrl: Deno.env.get("MS_LLM_BASE_URL") ||
        "http://host.docker.internal:8000",
    timeout: 30000, // 30 seconds
    headers: {
        "Content-Type": "application/json",
    },
};

/**
 * Utility class for interacting with the MS LLM API
 */
export class MSLLMClient {
    private options: MSLLMOptions;

    constructor(options: MSLLMOptions = {}) {
        this.options = { ...DEFAULT_OPTIONS, ...options };
    }

    /**
     * Make a request to the MS LLM API
     */
    async callAPI(
        endpoint: string = "/",
        requestData: MSLLMRequest = {},
        method: "GET" | "POST" | "PUT" | "DELETE" = "POST",
    ): Promise<RestResponse<ImportFromUrlResponse>> {
        const url = `${this.options.baseUrl}${endpoint}`;
        console.log("🔍 Calling API:", url);
        console.log("🔍 Request data:", requestData);
        console.log("🔍 Method:", method);

        try {
            const controller = new AbortController();
            const timeoutId = setTimeout(
                () => controller.abort(),
                this.options.timeout,
            );

            const headers: Record<string, string> = { ...this.options.headers };
            const apiKey = Deno.env.get("MS_LLM_API_KEY");
            if (apiKey) {
                headers["x-api-key"] = apiKey;
            }

            const response = await fetch(url, {
                method,
                headers,
                body: method !== "GET"
                    ? JSON.stringify(requestData)
                    : undefined,
                signal: controller.signal,
            });

            clearTimeout(timeoutId);

            if (!response.ok) {
                const error = await response.json();
                const errorObj = {
                    success: false,
                    error: error.detail.message,
                    error_code: error.detail.code,
                } as RestResponse<ImportFromUrlResponse>;

                console.log("🔍 Error object:", error);

                return errorObj;
            }

            const data = await response.json();
            return data as RestResponse<ImportFromUrlResponse>;
        } catch (error) {
            console.log("🔍 Error:", error);
            if (error instanceof Error) {
                if (error.name === "AbortError") {
                    throw new Error(
                        `Request timeout after ${this.options.timeout}ms`,
                    );
                }
                throw error;
            }
            throw new Error(`Unknown error occurred: ${error}`);
        }
    }

    /**
     * Get the response content from the API response
     */
    static getResponseContent(response: MSLLMResponse): string | null {
        if (response.error) {
            throw new Error(`API Error: ${response.error.message}`);
        }

        if (response.choices && response.choices.length > 0) {
            return response.choices[0].message?.content || null;
        }

        return null;
    }
}

/**
 * Health check function to verify the API is accessible
 */
export async function healthCheck(
    options: MSLLMOptions = {},
): Promise<boolean> {
    try {
        const client = new MSLLMClient(options);
        await client.callAPI("/health", {}, "GET");
        return true;
    } catch (error) {
        console.error("Health check failed:", error);
        return false;
    }
}
