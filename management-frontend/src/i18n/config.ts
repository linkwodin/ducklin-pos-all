import i18n from 'i18next';
import { initReactI18next } from 'react-i18next';
import LanguageDetector from 'i18next-browser-languagedetector';

import enTranslations from '../locales/en/translation.json';
import zhTWTranslations from '../locales/zh-TW/translation.json';
import zhCNTranslations from '../locales/zh-CN/translation.json';

type TranslationDict = Record<string, unknown>;

const PAGE_NAMESPACES = [
  'common',
  'layout',
  'shipment',
  'categories',
  'sectors',
  'catalogs',
  'assignProductToStore',
  'stock',
  'productLines',
  'storeDetail',
  'stockReport',
  'stocktake',
  'users',
  'usersPage',
  'stores',
  'storesPage',
  'devicesPage',
  'currencyRates',
  'companySettings',
  'wholesaleOrderDetail',
  'wholesaleOrderAudit',
  'wholesaleOrdersPage',
  'wholesaleShipments',
  'productBarcodeReference',
] as const;

function getNs(t: TranslationDict, name: string): TranslationDict {
  const s = t[name];
  return (s && typeof s === 'object' && !Array.isArray(s)) ? (s as TranslationDict) : {};
}

function buildResources(lang: TranslationDict) {
  const out: Record<string, TranslationDict> = {
    translation: lang,
  };
  PAGE_NAMESPACES.forEach((name) => {
    out[name] = getNs(lang, name);
  });
  return out;
}

i18n
  .use(LanguageDetector)
  .use(initReactI18next)
  .init({
    resources: {
      en: buildResources(enTranslations as TranslationDict),
      'zh-TW': buildResources(zhTWTranslations as TranslationDict),
      'zh-CN': buildResources(zhCNTranslations as TranslationDict),
    },
    fallbackLng: 'en',
    debug: false,
    interpolation: {
      escapeValue: false,
    },
  });

export default i18n;

