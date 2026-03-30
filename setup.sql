/*
================================================================================
Snowflake EC Analytics - 4時間パートナー向けハンズオン セットアップスクリプト
================================================================================

【概要】
このスクリプトは、ECサイト分析用のデータベース環境を構築し、
Gold層テーブルの復元とセマンティックビューの作成まで一括で実行します。
（通常版の setup.sql + backup.sql + Part4 のセマンティックビュー作成を統合）

【処理内容】
1. ウェアハウスなどの環境設定
2. データベースとスキーマの作成
3. ステージの作成（データ格納用）
4. GitHub連携の設定（API統合とGitリポジトリ）
5. GitHubからデータファイルの自動取得
6. Streamlit in Snowflake アプリのデプロイ
7. Snowflake Intelligence オブジェクトの作成
8. Gold層テーブルの復元（バックアップからリストア）
9. セマンティックビューの作成（Cortex Analyst向け）

【データソース】
GitHub Repository: https://github.com/sfc-gh-dmiyagawa/cortex-handson-jp

【実行方法】
このスクリプト全体を選択してSnowflakeで実行してください。

【所要時間】
約3〜5分

【次のステップ】
セットアップ完了後、part1_data_ingest.ipynb でデータのインポートを実行してください。

================================================================================
*/

-- ============================================================================
-- Step 1: 環境設定
-- ============================================================================
-- 管理者ロールとコンピュートウェアハウスを使用
USE ROLE ACCOUNTADMIN;

-- クロスリージョンコールのパラメータを有効化
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';

-- ウェアハウスの用意
CREATE WAREHOUSE IF NOT EXISTS GLACIERSTYLE_WH;
USE WAREHOUSE GLACIERSTYLE_WH;

SELECT '【Step 1】環境設定が完了しました' AS status;


-- ============================================================================
-- Step 2: データベースとスキーマの作成
-- ============================================================================
-- ECアナリティクス用のデータベースとスキーマを作成
CREATE OR REPLACE DATABASE GLACIERSTYLE_DB;
CREATE OR REPLACE SCHEMA GLACIERSTYLE_DB.EC_ANALYTICS_SCHEMA;
USE SCHEMA GLACIERSTYLE_DB.EC_ANALYTICS_SCHEMA;

SELECT '【Step 2】データベースとスキーマの作成が完了しました' AS status;


-- ============================================================================
-- Step 3: データステージの作成
-- ============================================================================
-- CSVファイルを格納するためのステージを作成（暗号化有効）
CREATE OR REPLACE STAGE GLACIERSTYLE_DB.EC_ANALYTICS_SCHEMA.DATA_STAGE 
  encryption = (type = 'snowflake_sse') 
  DIRECTORY = (ENABLE = TRUE);

CREATE OR REPLACE STAGE GLACIERSTYLE_DB.EC_ANALYTICS_SCHEMA.EXTRACTED_IMAGES_STAGE 
  encryption = (type = 'snowflake_sse') 
  DIRECTORY = (ENABLE = TRUE);

SELECT '【Step 3】データステージの作成が完了しました' AS status;


-- ============================================================================
-- Step 4: GitHub連携の設定
-- ============================================================================
-- GitHubからデータを取得するためのAPI統合を作成
CREATE OR REPLACE API INTEGRATION git_api_integration
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-dmiyagawa/')
  ENABLED = TRUE;

-- Gitリポジトリとの統合を作成
CREATE OR REPLACE GIT REPOSITORY GIT_INTEGRATION_FOR_HANDSON
  API_INTEGRATION = git_api_integration
  ORIGIN = 'https://github.com/sfc-gh-dmiyagawa/cortex-handson-jp.git';

SELECT '【Step 4】GitHub連携の設定が完了しました' AS status;


-- ============================================================================
-- Step 5: GitHubからデータファイルの取得
-- ============================================================================
-- リポジトリの内容を確認
ls @GIT_INTEGRATION_FOR_HANDSON/branches/4h_partner;

-- GitHubのdataディレクトリからすべてのファイルをステージにコピー
COPY FILES 
  INTO @GLACIERSTYLE_DB.EC_ANALYTICS_SCHEMA.DATA_STAGE 
  FROM @GIT_INTEGRATION_FOR_HANDSON/branches/4h_partner/data/;

-- ステージ内のファイルを確認
ls @GLACIERSTYLE_DB.EC_ANALYTICS_SCHEMA.DATA_STAGE;

SELECT '【Step 5】GitHubからのデータ取得が完了しました' AS status;


-- ============================================================================
-- Step 6: Streamlit in Snowflake アプリのデプロイ
-- ============================================================================
CREATE OR REPLACE STREAMLIT GLACIER_CREATIVE_STUDIO
    FROM @GIT_INTEGRATION_FOR_HANDSON/branches/4h_partner/streamlit_app
    MAIN_FILE = 'main.py'
    QUERY_WAREHOUSE = GLACIERSTYLE_WH
    COMMENT = 'GLACIER CREATIVE STUDIO - 広告クリエイティブ分析・企画支援プラットフォーム';

SELECT '【Step 6】Streamlit in Snowflakeアプリのデプロイが完了しました' AS status;


-- ============================================================================
-- Step 7: Snowflake Intelligence オブジェクトの作成
-- ============================================================================
CREATE OR REPLACE SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;

SELECT '【Step 7】Snowflake Intelligenceのオブジェクト作成が完了しました' AS status;


-- ============================================================================
-- Step 8: Gold層テーブルの復元（バックアップからリストア）
-- ============================================================================
-- ※ 通常版ではPart1〜Part4で順次構築するテーブルを、バックアップから一括復元します。
-- ※ これにより、Part2（名寄せ）に集中してハンズオンを進められます。

-- バックアップ用内部ステージの作成
CREATE OR REPLACE STAGE BACKUP_STAGE
    FILE_FORMAT = (
        TYPE = 'CSV'
        FIELD_DELIMITER = ','
        FIELD_OPTIONALLY_ENCLOSED_BY = '"'
        SKIP_HEADER = 0
        NULL_IF = ('NULL', 'null', '')
        EMPTY_FIELD_AS_NULL = TRUE
        COMPRESSION = GZIP
    )
    COMMENT = 'テーブルバックアップ用内部ステージ';

-- バックアップデータをGitからステージにコピー
COPY FILES 
  INTO @GLACIERSTYLE_DB.EC_ANALYTICS_SCHEMA.BACKUP_STAGE
  FROM @GIT_INTEGRATION_FOR_HANDSON/branches/main_v2/backup/;

-- Dimension層
CREATE OR REPLACE TABLE dim_customers (
    customer_id VARCHAR PRIMARY KEY,
    email VARCHAR,
    phone VARCHAR,
    last_name VARCHAR,
    first_name VARCHAR,
    gender VARCHAR,
    birth_date DATE,
    postal_code VARCHAR,
    prefecture VARCHAR,
    city VARCHAR,
    address VARCHAR,
    registration_date DATE,
    membership_tier VARCHAR,
    total_orders INTEGER,
    total_spent DECIMAL(12,2),
    last_order_date DATE,
    email_opt_in BOOLEAN,
    app_installed BOOLEAN
);

COPY INTO GLACIERSTYLE_DB.EC_ANALYTICS_SCHEMA.dim_customers
FROM @BACKUP_STAGE/dim_customers/
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' COMPRESSION = GZIP SKIP_HEADER = 1)
ON_ERROR = 'CONTINUE';

CREATE OR REPLACE TABLE dim_products (
    product_id VARCHAR PRIMARY KEY,
    product_name VARCHAR,
    product_name_en VARCHAR,
    category_l1 VARCHAR,
    category_l2 VARCHAR,
    category_l3 VARCHAR,
    brand VARCHAR,
    supplier_id VARCHAR,
    cost_price DECIMAL(10,2),
    list_price DECIMAL(10,2),
    current_price DECIMAL(10,2),
    stock_quantity INTEGER,
    product_status VARCHAR,
    launch_date DATE,
    description TEXT,
    weight_g INTEGER,
    dimensions VARCHAR
);

COPY INTO GLACIERSTYLE_DB.EC_ANALYTICS_SCHEMA.dim_products
FROM @BACKUP_STAGE/dim_products/
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' COMPRESSION = GZIP SKIP_HEADER = 1)
ON_ERROR = 'CONTINUE';

-- Fact層
CREATE OR REPLACE TABLE fact_orders (
    order_id VARCHAR PRIMARY KEY,
    order_datetime TIMESTAMP,
    customer_id VARCHAR,
    product_id VARCHAR,
    quantity INTEGER,
    unit_price DECIMAL(10,2),
    discount_amount DECIMAL(10,2),
    tax_amount DECIMAL(10,2),
    total_amount DECIMAL(10,2),
    payment_method VARCHAR,
    shipping_address_id VARCHAR,
    order_channel VARCHAR,
    campaign_id VARCHAR,
    order_status VARCHAR
);

ALTER SESSION SET TIMESTAMP_INPUT_FORMAT = 'YYYY/MM/DD HH24:MI:SS';

COPY INTO GLACIERSTYLE_DB.EC_ANALYTICS_SCHEMA.fact_orders
FROM @BACKUP_STAGE/fact_orders/
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' COMPRESSION = GZIP SKIP_HEADER = 1)
ON_ERROR = 'CONTINUE';

CREATE OR REPLACE TABLE fact_payments (
    payment_id VARCHAR PRIMARY KEY,
    order_id VARCHAR,
    payment_datetime TIMESTAMP,
    card_brand VARCHAR,
    card_last4 VARCHAR,
    payment_amount DECIMAL(10,2),
    authorization_code VARCHAR,
    payment_status VARCHAR,
    fraud_score DECIMAL(5,2),
    device_fingerprint VARCHAR,
    ip_address VARCHAR,
    billing_country VARCHAR
);

COPY INTO GLACIERSTYLE_DB.EC_ANALYTICS_SCHEMA.fact_payments
FROM @BACKUP_STAGE/fact_payments/
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' COMPRESSION = GZIP SKIP_HEADER = 1)
ON_ERROR = 'CONTINUE';

CREATE OR REPLACE TABLE fact_web_logs (
    log_id VARCHAR PRIMARY KEY,
    session_id VARCHAR,
    customer_id VARCHAR,
    event_timestamp TIMESTAMP,
    event_type VARCHAR,
    page_url VARCHAR,
    page_category VARCHAR,
    referrer_url VARCHAR,
    utm_source VARCHAR,
    utm_medium VARCHAR,
    utm_campaign VARCHAR,
    device_type VARCHAR,
    browser VARCHAR,
    os VARCHAR,
    time_on_page INTEGER,
    product_id VARCHAR
);

COPY INTO GLACIERSTYLE_DB.EC_ANALYTICS_SCHEMA.fact_web_logs
FROM @BACKUP_STAGE/fact_web_logs/
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' COMPRESSION = GZIP SKIP_HEADER = 1)
ON_ERROR = 'CONTINUE';

-- Gold層
CREATE OR REPLACE TABLE gold_sns_mentions_analyzed (
    POST_ID VARCHAR,
    PLATFORM VARCHAR,
    POST_TYPE VARCHAR,
    USERNAME VARCHAR,
    DISPLAY_NAME VARCHAR,
    CONTENT VARCHAR,
    POSTED_AT VARCHAR,
    LIKES NUMBER,
    RETWEETS NUMBER,
    REPLIES NUMBER,
    HASHTAGS ARRAY,
    MENTIONED_PRODUCTS ARRAY,
    MEDIA_URLS ARRAY,
    EXTRACTED_PRODUCT_NAME VARCHAR,
    EXTRACTED_CATEGORY VARCHAR,
    INQUIRY_TYPE VARCHAR,
    OVERALL_SENTIMENT VARCHAR,
    SENTIMENT VARCHAR,
    POST_CATEGORY VARCHAR,
    PROCESSED_AT VARCHAR
);

COPY INTO GLACIERSTYLE_DB.EC_ANALYTICS_SCHEMA.gold_sns_mentions_analyzed
FROM @BACKUP_STAGE/gold_sns_mentions_analyzed/
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' COMPRESSION = GZIP SKIP_HEADER = 1)
ON_ERROR = 'CONTINUE';

CREATE OR REPLACE TABLE gold_voice_logs (
    CALL_ID VARCHAR,
    SCENARIO_ID VARCHAR,
    AUDIO_FILE VARCHAR,
    CALL_DURATION_SEC NUMBER(10,2),
    CALL_START_TIME VARCHAR,
    CALL_END_TIME VARCHAR,
    CATEGORY VARCHAR,
    AGENT_ID VARCHAR,
    CUSTOMER_PHONE VARCHAR,
    CUSTOMER_ID VARCHAR,
    CALL_TYPE VARCHAR,
    TRANSCRIBED_TEXT_MASKED VARCHAR,
    SENTIMENT_RESULT OBJECT,
    OVERALL_SENTIMENT VARCHAR,
    SENTIMENT VARCHAR,
    CLASSIFICATION_RESULT OBJECT,
    INQUIRY_CATEGORY VARCHAR,
    TRANSCRIBED_TEXT_SUMMARY VARCHAR,
    PROCESSED_AT VARCHAR
);

COPY INTO GLACIERSTYLE_DB.EC_ANALYTICS_SCHEMA.gold_voice_logs
FROM @BACKUP_STAGE/gold_voice_logs/
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' COMPRESSION = GZIP SKIP_HEADER = 1)
ON_ERROR = 'CONTINUE';

CREATE OR REPLACE TABLE gold_ad_creative_analysis (
    CREATIVE_ID VARCHAR,
    CREATIVE_NAME VARCHAR,
    CREATIVE_TYPE VARCHAR,
    CAMPAIGN_ID VARCHAR,
    PLATFORM VARCHAR,
    TARGET_SEGMENT VARCHAR,
    COPY_TEXT VARCHAR,
    HEADLINE VARCHAR,
    CTA_TEXT VARCHAR,
    APPEAL_TYPE VARCHAR,
    CTA_TYPE VARCHAR,
    KEYWORDS VARCHAR,
    TARGET_EMOTION VARCHAR,
    USP VARCHAR,
    COPY_STYLE VARCHAR,
    SENTIMENT VARCHAR,
    IMPRESSIONS NUMBER,
    CLICKS NUMBER,
    CONVERSIONS NUMBER,
    SPEND NUMBER(10,2),
    CTR FLOAT,
    CVR FLOAT,
    CPA NUMBER(16,8),
    VISUAL_ANALYSIS_RAW_JSON VARIANT,
    IMAGE_STYLE VARCHAR,
    PROCESSED_AT VARCHAR
);

COPY INTO GLACIERSTYLE_DB.EC_ANALYTICS_SCHEMA.gold_ad_creative_analysis
FROM @BACKUP_STAGE/gold_ad_creative_analysis/
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' COMPRESSION = GZIP SKIP_HEADER = 1)
ON_ERROR = 'CONTINUE';

CREATE OR REPLACE TABLE gold_faq_documents (
    RELATIVE_PATH VARCHAR,
    FILE_URL VARCHAR,
    SIZE NUMBER,
    LAST_MODIFIED VARCHAR,
    RAW_VALUE VARIANT,
    CONTENT_CHUNK VARCHAR,
    SUMMARY_CATEGORY VARCHAR
);

COPY INTO GLACIERSTYLE_DB.EC_ANALYTICS_SCHEMA.gold_faq_documents
FROM @BACKUP_STAGE/gold_faq_documents/
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' COMPRESSION = GZIP SKIP_HEADER = 1)
ON_ERROR = 'CONTINUE';

CREATE OR REPLACE TABLE gold_operation_manuals (
    RELATIVE_PATH VARCHAR,
    FILE_URL VARCHAR,
    SIZE NUMBER,
    LAST_MODIFIED VARCHAR,
    CONTENT_CHUNK VARCHAR
);

COPY INTO GLACIERSTYLE_DB.EC_ANALYTICS_SCHEMA.gold_operation_manuals
FROM @BACKUP_STAGE/gold_operation_manuals/
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' COMPRESSION = GZIP SKIP_HEADER = 1)
ON_ERROR = 'CONTINUE';

CREATE OR REPLACE TABLE gold_sns_mentions_with_product_master (
    POST_ID VARCHAR,
    PLATFORM VARCHAR,
    POST_TYPE VARCHAR,
    USERNAME VARCHAR,
    DISPLAY_NAME VARCHAR,
    CONTENT VARCHAR,
    POSTED_AT VARCHAR,
    LIKES NUMBER,
    RETWEETS NUMBER,
    REPLIES NUMBER,
    HASHTAGS ARRAY,
    MENTIONED_PRODUCTS ARRAY,
    MEDIA_URLS ARRAY,
    EXTRACTED_PRODUCT_NAME VARCHAR,
    EXTRACTED_CATEGORY VARCHAR,
    INQUIRY_TYPE VARCHAR,
    OVERALL_SENTIMENT VARCHAR,
    SENTIMENT VARCHAR,
    POST_CATEGORY VARCHAR,
    PROCESSED_AT VARCHAR,
    PRODUCT_ID VARCHAR,
    PRODUCT_NAME VARCHAR,
    PRODUCT_NAME_EN VARCHAR,
    CATEGORY_L1 VARCHAR,
    CATEGORY_L2 VARCHAR,
    CATEGORY_L3 VARCHAR,
    BRAND VARCHAR,
    SUPPLIER_ID VARCHAR,
    COST_PRICE NUMBER(10,2),
    LIST_PRICE NUMBER(10,2),
    CURRENT_PRICE NUMBER(10,2),
    STOCK_QUANTITY NUMBER,
    PRODUCT_STATUS VARCHAR,
    LAUNCH_DATE DATE,
    DESCRIPTION VARCHAR,
    WEIGHT_G NUMBER,
    DIMENSIONS VARCHAR,
    SIMILARITY FLOAT
);

COPY INTO GLACIERSTYLE_DB.EC_ANALYTICS_SCHEMA.gold_sns_mentions_with_product_master
FROM @BACKUP_STAGE/gold_sns_mentions_with_product_master/
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' COMPRESSION = GZIP SKIP_HEADER = 1)
ON_ERROR = 'CONTINUE';

CREATE OR REPLACE TABLE gold_supplier_product_mapping (
    SUPPLIER_PRODUCT_ID VARCHAR,
    SUPPLIER_PRODUCT_NAME VARCHAR,
    SUPPLIER_NAME VARCHAR,
    MATCHED_PRODUCT_ID VARCHAR,
    MATCHED_PRODUCT_NAME VARCHAR,
    MATCH_SCORE FLOAT,
    MATCH_METHOD VARCHAR
);

COPY INTO GLACIERSTYLE_DB.EC_ANALYTICS_SCHEMA.gold_supplier_product_mapping
FROM @BACKUP_STAGE/gold_supplier_product_mapping/
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' COMPRESSION = GZIP SKIP_HEADER = 1)
ON_ERROR = 'CONTINUE';

SELECT '【Step 8】Gold層テーブルの復元が完了しました' AS status;


-- ============================================================================
-- Step 9: セマンティックビューの作成（Cortex Analyst向け）
-- ============================================================================
-- Cortex Agentで自然言語クエリを実行するためのセマンティックビューを作成
CREATE OR REPLACE SEMANTIC VIEW glacierstyle_db.ec_analytics_schema.ec_analysis_semantic_view
    TABLES (
        customers AS glacierstyle_db.ec_analytics_schema.dim_customers PRIMARY KEY (customer_id),
        products AS glacierstyle_db.ec_analytics_schema.dim_products PRIMARY KEY (product_id),
        orders AS glacierstyle_db.ec_analytics_schema.fact_orders PRIMARY KEY (order_id),
        payments AS glacierstyle_db.ec_analytics_schema.fact_payments PRIMARY KEY (payment_id),
        web_logs AS glacierstyle_db.ec_analytics_schema.fact_web_logs PRIMARY KEY (log_id)
    )
    RELATIONSHIPS (
        orders_to_customers AS orders (customer_id) REFERENCES customers,
        orders_to_products AS orders (product_id) REFERENCES products,
        payments_to_orders AS payments (order_id) REFERENCES orders
    )
    FACTS (
        orders.order_total AS total_amount,
        payments.pay_amt AS payment_amount
    )
    DIMENSIONS (
        customers.cust_name AS CONCAT(last_name, first_name),
        products.prod_name AS product_name,
        orders.order_date AS order_datetime
    )
    METRICS (
        orders.total_sales AS SUM(total_amount),
        orders.order_count AS COUNT(order_id)
    )
    COMMENT = 'GlacierStyle ECサイト分析用セマンティックビュー';

SELECT '【Step 9】セマンティックビューの作成が完了しました' AS status;


-- ============================================================================
-- 完了メッセージ
-- ============================================================================
SELECT '
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  環境セットアップが完了しました！（4時間パートナー版）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  データベース: GLACIERSTYLE_DB
  スキーマ: EC_ANALYTICS_SCHEMA
  ステージ: DATA_STAGE（データファイル格納済み）
  GitHub連携: GIT_INTEGRATION_FOR_HANDSON
  Streamlitアプリ: GLACIER_CREATIVE_STUDIO
  Gold層テーブル: 復元済み（11テーブル）
  セマンティックビュー: ec_analysis_semantic_view

【次のステップ】
part1_data_ingest.ipynb を開いてデータのインポートを実行してください。

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
' AS setup_complete;
