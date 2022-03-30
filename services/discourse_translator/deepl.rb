# frozen_string_literal: true

require_relative 'base'
require 'json'

module DiscourseTranslator
  class Deepl < Base
    PRO_TRANSLATE_URI = "https://api.deepl.com/v2/translate".freeze
    FREE_TRANSLATE_URI = "https://api-free.deepl.com/v2/translate".freeze
    PRO_DETECT_URI = "https://api.deepl.com/v2/translate".freeze
    FREE_DETECT_URI = "https://api-free.deepl.com/v2/translate".freeze
    PRO_SUPPORT_URI = "https://api.deepl.com/v2/languages".freeze
    FREE_SUPPORT_URI = "https://api-free.deepl.com/v2/languages".freeze
    #SUPPORT_URI = "https://www.googleapis.com/language/translate/v2/languages".freeze
    MAXLENGTH = 5000
    SUPPORTED_LANG = {
      en: 'EN-US',
      bg: 'BG',
      en_GB: 'EN-GB',
      en_US: 'EN-US',
      cs: 'CS',
      da: 'DA',
      de: 'DE',
      el: 'EL',
      es: 'ES',
      fi: 'FI',
      fr: 'FR',
      it: 'IT',
      et: 'ET',
      hu: 'HU',
      ja: 'JA',
      lt: 'LT',
      lv: 'LV',
      nl: 'NL',
      pl: 'PL',
      pt: 'PT-PT',
      pt_br: 'PT-BR',
      ro: 'RO',
      ru: 'RU',
      sk: 'SK',
      sl: 'SL',
      sv: 'SV',
      zh_CN: 'ZH',
      zh_TW: 'ZH'
    }

    def self.access_token_key
      "deepl-translator"
    end

    def self.detect_uri 
      access_token.match(":fx") ? FREE_DETECT_URI : PRO_DETECT_URI
    end

    def self.translate_uri 
      access_token.match(":fx") ? FREE_TRANSLATE_URI : PRO_TRANSLATE_URI
    end

    def self.support_uri 
      access_token.match(":fx") ? FREE_SUPPORT_URI : PRO_SUPPORT_URI
    end

    def self.access_token
      if SiteSetting.translator_deepl_api_key.match(":fx")
        @detect_uri = FREE_DETECT_URI
        @translate_uri = FREE_TRANSLATE_URI
      else
        @detect_uri = PRO_DETECT_URI
        @translate_uri = PRO_TRANSLATE_URI
      end        
      SiteSetting.translator_deepl_api_key || (raise TranslatorError.new("NotFound: deepl Api Key not set."))
    end

    def self.detect(post)
      puts "detect"
      return nil unless translate_supported?('ignored', I18n.locale)
      puts "GOing to try to detect anyway"
      r=result(detect_uri,
          { text: post.cooked.truncate(MAXLENGTH, omission: nil),
            target_lang: SUPPORTED_LANG[I18n.locale]
          }
          )
      language = r[0]['detected_source_language']
      puts "Detected language: #{language}"
      post.custom_fields[DiscourseTranslator::DETECTED_LANG_CUSTOM_FIELD] ||= language          
    end

    def self.broken_translate_supported?(source, target)
      # NOTE: Source is ignored, since we can't know until it's too late
      puts "supported? T: #{target}--> #{SUPPORTED_LANG[target.to_sym]}. S: #{source}"
      if SUPPORTED_LANG[target.to_sym]
        puts "Supported"
        return true
      else
        puts 'not supported'
        return false
      end
      
      res = result(SUPPORT_URI, target: SUPPORTED_LANG[target])
      res["languages"].any? { |obj| obj["language"] == source }
      SUPPORTED_LANG[target.to_sym]
    end

    def self.translate_supported?(source, target)
      return true
      puts "Checking supported from #{support_uri}"
      # just ignore the source language since we can't know before it's too late
      res = result(support_uri, type: "target")
      puts "translate Got #{res}"
      #puts "plucked: #{res.pluck(:language)}"
      target.in?(res.pluck(:language))
    end

    def self.translate(post)
      # don't bother with detecting...
      ok_to_translate = translate_supported?('detected_lang', I18n.locale)
      raise I18n.t('translator.failed') unless ok_to_translate
      detected_lang = detect(post)

      translated_text = from_custom_fields(post) do
        res = result(translate_uri,
          text: post.cooked.truncate(MAXLENGTH, omission: nil),
          #asource_lang: detected_lang,
          tag_handling: "xml",
          target_lang: SUPPORTED_LANG[I18n.locale]
        )
        puts "Translation: #{res[0]['text']}"
        res[0]["text"]
      end

      [detected_lang, translated_text]
    end    

    def self.result(url, body)
      response = Excon.post(url,
      body: URI.encode_www_form(body),
        headers: { "Content-Type" => "application/x-www-form-urlencoded",
                    "Authorization" => "DeepL-Auth-Key #{access_token}"  
        }
      )
      body = nil
      begin
        body = JSON.parse(response.body)
      rescue JSON::ParserError
      end

      if response.status != 200
        raise TranslatorError.new(body   || response.inspect)
      else
        body["translations"]
      end
    end
  end
end
