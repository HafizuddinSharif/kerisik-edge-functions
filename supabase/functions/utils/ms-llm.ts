// Utility function for calling the MS LLM API at http://127.0.0.1:8000

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
    // baseUrl: "https://kerisik-fastapi-production.up.railway.app",
    baseUrl: "http://host.docker.internal:8000",
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
    ): Promise<MSLLMResponse> {
        const url = `${this.options.baseUrl}${endpoint}`;

        try {
            const controller = new AbortController();
            const timeoutId = setTimeout(
                () => controller.abort(),
                this.options.timeout,
            );

            const response = await fetch(url, {
                method,
                headers: this.options.headers,
                body: method !== "GET"
                    ? JSON.stringify(requestData)
                    : undefined,
                signal: controller.signal,
            });

            clearTimeout(timeoutId);

            if (!response.ok) {
                throw new Error(
                    `HTTP error! status: ${response.status} - ${response.statusText}`,
                );
            }

            const data = await response.json();
            return data as MSLLMResponse;
        } catch (error) {
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
     * Send a simple prompt to the LLM
     */
    async sendPrompt(
        prompt: string,
        options: Partial<MSLLMRequest> = {},
    ): Promise<MSLLMResponse> {
        const requestData: MSLLMRequest = {
            prompt,
            ...options,
        };

        return this.callAPI("/", requestData);
    }

    /**
     * Send a conversation-style message to the LLM
     */
    async sendMessage(
        messages: Array<
            { role: "user" | "assistant" | "system"; content: string }
        >,
        options: Partial<MSLLMRequest> = {},
    ): Promise<MSLLMResponse> {
        const requestData: MSLLMRequest = {
            messages,
            ...options,
        };

        return this.callAPI("/", requestData);
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
 * Convenience function for quick API calls
 */
export async function callMSLLM(
    requestData: MSLLMRequest,
    options: MSLLMOptions = {},
): Promise<MSLLMResponse> {
    const client = new MSLLMClient(options);
    return client.callAPI("/", requestData);
}

/**
 * Convenience function for simple prompt requests
 */
export async function sendPrompt(
    prompt: string,
    options: MSLLMOptions & Partial<MSLLMRequest> = {},
): Promise<string | null> {
    const { baseUrl, timeout, headers, ...requestOptions } = options;
    const client = new MSLLMClient({ baseUrl, timeout, headers });

    const response = await client.sendPrompt(prompt, requestOptions);
    return MSLLMClient.getResponseContent(response);
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
