/**
 @name: 额度查询模板
 @Descripttion: 提供余额及订阅额度查询的可编辑 JavaScript 模板。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-08 14:56:06
 @LastEditTime: 2026-09-08 14:56:06
 @FilePath: Sources/Providers/QueryTemplates.swift
 */
import Foundation

enum QueryTemplate: String, Codable, CaseIterable, Identifiable {
    case native, custom, general, newapi, sub2api
    case deepseek, stepfun, siliconflow, openrouter, novita
    case glm, kimi, minimax
    var id: String { rawValue }
    var title: String {
        switch self {
        case .native: return String(localized: "Built-in query")
        case .custom: return String(localized: "Custom JavaScript")
        case .general: return String(localized: "General balance")
        case .newapi: return "NewAPI"
        case .sub2api: return "Sub2API"
        case .deepseek: return "DeepSeek"
        case .stepfun: return "StepFun"
        case .siliconflow: return "SiliconFlow"
        case .openrouter: return "OpenRouter"
        case .novita: return "Novita AI"
        case .glm: return String(localized: "GLM Token Plan")
        case .kimi: return String(localized: "Kimi Token Plan")
        case .minimax: return String(localized: "MiniMax Token Plan")
        }
    }

    var baseURL: String {
        switch self {
        case .deepseek: return "https://api.deepseek.com"
        case .stepfun: return "https://api.stepfun.com"
        case .siliconflow: return "https://api.siliconflow.cn"
        case .openrouter: return "https://openrouter.ai"
        case .novita: return "https://api.novita.ai"
        case .glm: return "https://open.bigmodel.cn"
        case .kimi: return "https://api.kimi.com"
        case .minimax: return "https://api.minimaxi.com"
        default: return ""
        }
    }

    var code: String {
        let path: String
        let extractor: String
        var headers = "Authorization: 'Bearer ' + apiKey"
        switch self {
        case .native: return ""
        case .custom:
            path = ""
            extractor = "return { key: 'balance', label: 'Balance', remaining: response.balance, unit: 'USD' };"
        case .general:
            path = "/user/balance"
            extractor = "return { key: 'balance', label: 'Balance', remaining: response.balance, unit: 'USD' };"
        case .newapi:
            path = "/api/user/self"
            headers = "Authorization: 'Bearer ' + accessToken, 'New-Api-User': userId"
            extractor = """
            if (!response.success || !response.data) throw new Error('Invalid response');
            const data = response.data;
            return { key: 'balance', label: data.group || 'NewAPI',
              remaining: quotaNumber(data.quota) / 500000,
              used: quotaNumber(data.used_quota) / 500000, unit: 'USD' };
            """
        case .sub2api:
            path = "/v1/usage"
            extractor = """
            if (response.is_active === false || response.isValid === false) throw new Error('Inactive subscription');
            const plan = response.subscription || {};
            const unit = response.unit || response.quota?.unit || 'USD';
            const dailyReset = new Date();
            dailyReset.setHours(24, 0, 0, 0);
            const weeklyStart = plan.weekly_window_start ? new Date(plan.weekly_window_start) : null;
            const weeklyReset = weeklyStart && Number.isFinite(weeklyStart.getTime())
              ? new Date(weeklyStart.getTime() + 7 * 24 * 60 * 60 * 1000).toISOString() : undefined;
            const items = ['daily', 'weekly', 'monthly'].filter(p => Number(plan[p + '_limit_usd']) > 0).map(p => ({
              key: p, label: p, total: Number(plan[p + '_limit_usd']),
              used: quotaNumber(plan[p + '_usage_usd'] ?? 0), unit,
              nextReset: plan[p + '_reset_at'] || (p === 'daily' ? dailyReset.toISOString()
                : p === 'weekly' ? weeklyReset : plan.expires_at)
            }));
            if (items.length) return items;
            const unlimited = ['daily', 'weekly', 'monthly'].every(p => {
              const value = plan[p + '_limit_usd'];
              return value !== null && value !== undefined && String(value).trim() !== '' && Number(value) === 0;
            });
            return { key: 'balance', label: response.planName || 'Sub2API', unlimited, unit,
              remaining: response.remaining ?? response.quota?.remaining ?? response.balance };
            """
        case .deepseek:
            path = "/user/balance"
            extractor = """
            return response.balance_infos.map((item, index) => ({
              key: item.currency || String(index), label: 'Balance',
              remaining: quotaNumber(item.total_balance), unit: item.currency
            }));
            """
        case .stepfun:
            path = "/v1/accounts"
            extractor = "return { key: 'balance', label: 'Balance', remaining: quotaNumber(response.balance), unit: 'CNY' };"
        case .siliconflow:
            path = "/v1/user/info"
            extractor = "return { key: 'balance', label: 'Balance', remaining: quotaNumber(response.data.totalBalance), unit: 'CNY' };"
        case .openrouter:
            path = "/api/v1/credits"
            extractor = "return { key: 'balance', label: 'Balance', remaining: quotaNumber(response.data.total_credits) - quotaNumber(response.data.total_usage), used: quotaNumber(response.data.total_usage), unit: 'USD' };"
        case .novita:
            path = "/v3/user/balance"
            extractor = "return { key: 'balance', label: 'Balance', remaining: quotaNumber(response.availableBalance) / 10000, unit: 'USD' };"
        case .glm:
            path = "/api/monitor/usage/quota/limit"
            headers = "Authorization: apiKey"
            extractor = """
            if (response.success === false || (response.code !== undefined && ![0, 200].includes(Number(response.code)))) throw new Error('Invalid response');
            return response.data.limits.map((item, index) => ({
              key: item.type === 'TIME_LIMIT' ? 'mcp' : item.unit === 3 && item.number === 5 ? 'session'
                : item.unit === 6 && item.number === 1 ? 'weekly' : 'window-' + item.unit + 'x' + item.number,
              label: item.type === 'TIME_LIMIT' ? 'MCP' : item.unit === 3 && item.number === 5 ? 'Session'
                : item.unit === 6 && item.number === 1 ? 'Weekly' : item.type || 'Quota',
              total: Number(item.usage) > 0 ? Number(item.usage) : 100,
              used: Number(item.usage) > 0 ? Number(item.currentValue) : Number(item.percentage),
              nextReset: item.nextResetTime ? new Date(Number(item.nextResetTime)).toISOString() : undefined
            }));
            """
        case .kimi:
            path = "/coding/v1/usages"
            extractor = """
            const items = (response.limits || []).map((item, index) => ({
              key: 'session-' + index, label: 'Session', total: Number(item.detail.limit),
              remaining: Number(item.detail.remaining), nextReset: item.detail.resetTime
            }));
            if (response.usage) items.push({ key: 'weekly', label: 'Weekly',
              total: Number(response.usage.limit), remaining: Number(response.usage.remaining),
              nextReset: response.usage.resetTime });
            return items;
            """
        case .minimax:
            path = "/v1/api/openplatform/coding_plan/remains"
            extractor = """
            if (response.base_resp?.status_code) throw new Error('Invalid response');
            const item = response.model_remains[0];
            return ['interval', 'weekly'].filter(p => Number(item['current_' + p + '_total_count']) > 0).map(p => ({
              key: p, label: p === 'interval' ? 'Session' : 'Weekly',
              total: Number(item['current_' + p + '_total_count']),
              remaining: Number(item['current_' + p + '_usage_count']),
              nextReset: item[p === 'interval' ? 'end_time' : 'weekly_end_time']
            }));
            """
        }
        return """
        ({
          request: {
            url: baseUrl.replace(/\\/$/, '') + '\(path)',
            method: 'GET',
            headers: { \(headers) }
          },
          extractor: function(response) {
            function quotaNumber(value) {
              if ((typeof value !== 'number' && typeof value !== 'string')
                || String(value).trim() === '' || !Number.isFinite(Number(value))) {
                throw new Error('Invalid quota value');
              }
              return Number(value);
            }
            \(extractor)
          }
        })
        """
    }
}
