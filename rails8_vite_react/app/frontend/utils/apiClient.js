class ApiClient {
  static baseURL = import.meta.env.VITE_API_BASE_URL;

  static async request(endpoint, options = {}) {
    const url = `${this.baseURL}${endpoint}`;
    const defaultHeaders = {
      'Content-Type': 'application/json'
    };
    const config = {
      method: options.method || 'GET',
      headers: {
        ...defaultHeaders,
        ...(options.headers || {})
      },
      body: options.body
    };

    try {
      console.log('request', url, config);
      const response = await fetch(url, config);
      const data = await response.json();

      if (!response.ok) {
        throw new Error(data.error || `HTTP error! status: ${response.status}`);
      }
      console.log('response', response, data);
      return data;
    } catch (error) {
      console.error('API request failed:', error);
      throw error;
    }
  }

  static async get(endpoint, headers = {}) {
    return this.request(endpoint, { method: 'GET', headers });
  }

  static async post(endpoint, data = {}, headers = {}) {
    return this.request(endpoint, {
      method: 'POST',
      headers,
      body: JSON.stringify(data)
    });
  }

  static async delete(endpoint, data = {}, headers = {}) {
    return this.request(endpoint, {
      method: 'DELETE',
      headers,
      body: JSON.stringify(data)
    });
  }
}
export default ApiClient;
