--
-- PostgreSQL database dump
--

\restrict yfsenuV7nGZy2heOQ6Ec9ALJmjNSThE3Nei882eunnzTod4jMOEE4z26R9EESpL

-- Dumped from database version 17.11 (Debian 17.11-0+deb13u1)
-- Dumped by pg_dump version 17.11 (Debian 17.11-0+deb13u1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: group_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.group_permissions (
    group_id integer NOT NULL,
    permission_id integer NOT NULL
);


--
-- Name: group_permissions_old; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.group_permissions_old (
    group_id integer NOT NULL,
    dashboard boolean DEFAULT false,
    pending boolean DEFAULT false,
    approved boolean DEFAULT false,
    denied boolean DEFAULT false,
    settings boolean DEFAULT false,
    users boolean DEFAULT false,
    groups boolean DEFAULT false,
    authentication boolean DEFAULT false,
    settings_general boolean DEFAULT false,
    settings_appearance boolean DEFAULT false,
    settings_dns boolean DEFAULT false,
    settings_security boolean DEFAULT false,
    settings_notifications boolean DEFAULT false,
    settings_technitium boolean DEFAULT false
);


--
-- Name: groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.groups (
    id integer NOT NULL,
    group_name character varying(100) NOT NULL,
    description text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: groups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.groups_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.groups_id_seq OWNED BY public.groups.id;


--
-- Name: page_tabs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.page_tabs (
    id integer NOT NULL,
    tab_group character varying(100) NOT NULL,
    tab_name character varying(100) NOT NULL,
    tab_href character varying(255) DEFAULT ''::character varying NOT NULL,
    tab_permission character varying(100) DEFAULT ''::character varying NOT NULL,
    tab_alternates character varying(255) DEFAULT ''::character varying NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: page_tabs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.page_tabs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: page_tabs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.page_tabs_id_seq OWNED BY public.page_tabs.id;


--
-- Name: permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.permissions (
    id integer NOT NULL,
    permission_key character varying(100) NOT NULL,
    permission_name character varying(255) NOT NULL,
    parent_id integer
);


--
-- Name: permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.permissions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: permissions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.permissions_id_seq OWNED BY public.permissions.id;


--
-- Name: portal_auth; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.portal_auth (
    id integer NOT NULL,
    username character varying(255) NOT NULL,
    password_hash character varying(255) NOT NULL,
    is_disabled boolean DEFAULT false NOT NULL,
    must_change_password boolean DEFAULT false NOT NULL,
    technitium_synced boolean DEFAULT true NOT NULL,
    migrated_from_technitium boolean DEFAULT false NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    totp_secret character varying(255),
    totp_pending_secret character varying(255),
    totp_enabled boolean DEFAULT false NOT NULL,
    totp_last_timestep bigint
);


--
-- Name: portal_auth_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.portal_auth_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: portal_auth_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.portal_auth_id_seq OWNED BY public.portal_auth.id;


--
-- Name: portal_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.portal_settings (
    setting_key character varying(100) NOT NULL,
    setting_value text NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.requests (
    id integer NOT NULL,
    domain character varying(255),
    client_ip character varying(45),
    reason character varying(255),
    requested_at timestamp without time zone DEFAULT now(),
    status character varying(20) DEFAULT 'Pending'::character varying,
    approved_at timestamp without time zone,
    denied_at timestamp without time zone,
    allowed_until timestamp without time zone,
    deny_reason character varying(100),
    requested_by character varying(100),
    allow_minutes integer,
    submitted_by character varying(100)
);


--
-- Name: requests_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.requests_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: requests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.requests_id_seq OWNED BY public.requests.id;


--
-- Name: settings_field_sections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.settings_field_sections (
    id integer NOT NULL,
    section_name character varying(100) NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: settings_field_sections_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.settings_field_sections_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: settings_field_sections_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.settings_field_sections_id_seq OWNED BY public.settings_field_sections.id;


--
-- Name: settings_fields; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.settings_fields (
    id integer NOT NULL,
    section_id integer NOT NULL,
    field_name character varying(100) NOT NULL,
    field_href character varying(255) DEFAULT ''::character varying NOT NULL,
    field_permission character varying(100) DEFAULT ''::character varying NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: settings_fields_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.settings_fields_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: settings_fields_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.settings_fields_id_seq OWNED BY public.settings_fields.id;


--
-- Name: user_custom_field_sections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_custom_field_sections (
    id integer NOT NULL,
    section_name character varying(100) NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: user_custom_field_sections_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_custom_field_sections_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_custom_field_sections_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_custom_field_sections_id_seq OWNED BY public.user_custom_field_sections.id;


--
-- Name: user_custom_field_values; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_custom_field_values (
    user_id integer NOT NULL,
    field_id integer NOT NULL,
    field_value text,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: user_custom_fields; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_custom_fields (
    id integer NOT NULL,
    field_name character varying(100) NOT NULL,
    field_key character varying(100) NOT NULL,
    field_type character varying(30) DEFAULT 'text'::character varying NOT NULL,
    required boolean DEFAULT false NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    section_id integer NOT NULL,
    prepend character varying(50),
    append character varying(50)
);


--
-- Name: user_custom_fields_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_custom_fields_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_custom_fields_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_custom_fields_id_seq OWNED BY public.user_custom_fields.id;


--
-- Name: user_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_groups (
    username character varying(255) NOT NULL,
    group_id integer NOT NULL
);


--
-- Name: user_management_tabs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_management_tabs (
    id integer NOT NULL,
    tab_name character varying(100) NOT NULL,
    tab_href character varying(255) DEFAULT ''::character varying NOT NULL,
    tab_permission character varying(100) DEFAULT ''::character varying NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: user_management_tabs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_management_tabs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_management_tabs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_management_tabs_id_seq OWNED BY public.user_management_tabs.id;


--
-- Name: user_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_profiles (
    id integer NOT NULL,
    username character varying(255) NOT NULL,
    display_name character varying(255),
    email_address character varying(255),
    country_code character varying(10),
    mobile_number character varying(50),
    group_id integer,
    status character varying(20) DEFAULT 'Active'::character varying,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    surname character varying(255),
    department character varying(255),
    photo character varying(500)
);


--
-- Name: user_profiles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_profiles_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_profiles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_profiles_id_seq OWNED BY public.user_profiles.id;


--
-- Name: groups id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.groups ALTER COLUMN id SET DEFAULT nextval('public.groups_id_seq'::regclass);


--
-- Name: page_tabs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.page_tabs ALTER COLUMN id SET DEFAULT nextval('public.page_tabs_id_seq'::regclass);


--
-- Name: permissions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permissions ALTER COLUMN id SET DEFAULT nextval('public.permissions_id_seq'::regclass);


--
-- Name: portal_auth id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.portal_auth ALTER COLUMN id SET DEFAULT nextval('public.portal_auth_id_seq'::regclass);


--
-- Name: requests id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.requests ALTER COLUMN id SET DEFAULT nextval('public.requests_id_seq'::regclass);


--
-- Name: settings_field_sections id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.settings_field_sections ALTER COLUMN id SET DEFAULT nextval('public.settings_field_sections_id_seq'::regclass);


--
-- Name: settings_fields id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.settings_fields ALTER COLUMN id SET DEFAULT nextval('public.settings_fields_id_seq'::regclass);


--
-- Name: user_custom_field_sections id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_custom_field_sections ALTER COLUMN id SET DEFAULT nextval('public.user_custom_field_sections_id_seq'::regclass);


--
-- Name: user_custom_fields id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_custom_fields ALTER COLUMN id SET DEFAULT nextval('public.user_custom_fields_id_seq'::regclass);


--
-- Name: user_management_tabs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_management_tabs ALTER COLUMN id SET DEFAULT nextval('public.user_management_tabs_id_seq'::regclass);


--
-- Name: user_profiles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_profiles ALTER COLUMN id SET DEFAULT nextval('public.user_profiles_id_seq'::regclass);


--
-- Data for Name: group_permissions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.group_permissions (group_id, permission_id) FROM stdin;
1	52
1	62
1	63
1	53
1	108
1	66
1	69
1	70
1	109
1	64
1	65
1	110
1	111
1	55
1	78
1	81
1	82
1	83
1	98
1	79
1	80
1	56
1	101
1	84
1	85
1	102
1	103
1	105
1	106
1	107
1	57
1	87
1	88
1	89
1	99
1	92
1	54
9	58
9	59
9	60
9	61
9	62
1	71
1	72
1	74
1	77
1	93
1	94
1	95
1	58
1	59
1	60
1	61
1	91
1	112
1	114
1	115
9	114
9	115
9	112
1	117
\.


--
-- Data for Name: group_permissions_old; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.group_permissions_old (group_id, dashboard, pending, approved, denied, settings, users, groups, authentication, settings_general, settings_appearance, settings_dns, settings_security, settings_notifications, settings_technitium) FROM stdin;
\.


--
-- Data for Name: groups; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.groups (id, group_name, description, created_at) FROM stdin;
9	Operators	Can approve Requests	2026-09-14 11:05:12.527727
11	Unassigned	Unassigned	2026-09-18 22:42:57.578956
1	Administrators	Full access	2026-09-13 21:49:43.576463
\.


--
-- Data for Name: page_tabs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.page_tabs (id, tab_group, tab_name, tab_href, tab_permission, tab_alternates, sort_order, created_at) FROM stdin;
1	https-ssl.php	Portal Certificate	https-ssl.php	HTTPS/SSL		0	2026-09-23 12:39:45.080079
2	https-ssl.php	DNS Server Certificate	https-ssl-dns.php	HTTPS/SSL		1	2026-09-23 12:39:45.080079
3	notifications-email.php	Email	notifications-email.php	Email Notifications		0	2026-09-23 12:39:45.080079
4	notifications-email.php	Push	notifications-push.php	Push Notifications		1	2026-09-23 12:39:45.080079
5	notifications-email.php	WhatsApp	notifications-whatsapp.php	WhatsApp		2	2026-09-23 12:39:45.080079
6	notifications-email.php	Telegram	notifications-telegram.php	Telegram		3	2026-09-23 12:39:45.080079
7	appearance-logo.php	Logo	appearance-logo.php	Logo		0	2026-09-23 12:39:45.080079
8	appearance-logo.php	Banner	appearance-banner.php	Banner		1	2026-09-23 12:39:45.080079
9	appearance-logo.php	Theme	appearance-theme.php	Theme	appearance-theme-basic.php	2	2026-09-23 12:39:45.080079
10	appearance-logo.php	Login Page	appearance-login.php	Login		3	2026-09-23 12:39:45.080079
11	appearance-logo.php	Sidebar	appearance-sidebar.php	Sidebar		4	2026-09-23 12:39:45.080079
12	appearance-logo.php	User Disclaimer	appearance-user-disclaimer.php	User Disclaimer		5	2026-09-23 12:39:45.080079
13	time-zone.php	Time Zone	time-zone.php	Time Zone		0	2026-09-23 12:40:38.61756
14	timeout.php	Session Timeout	timeout.php	Session Timeout		0	2026-09-23 12:40:38.61756
16	notifications-email.php	Pushbullet	notifications-pushbullet.php	Pushbullet		4	2026-09-23 12:56:15.638796
19	monitor-login.php	Pushbullet	monitor-pushbullet.php	Pushbullet		1	2026-09-23 16:41:14.703443
20	monitor-login.php	Email	monitor-email.php	Email Notifications		1	2026-09-23 16:47:36.623386
29	technitium.php	Network Proxy	network-proxy.php	Network Proxy		5	2026-09-23 20:06:57.540459
30	technitium.php	DHCP	dhcp.php	DHCP		6	2026-09-23 20:06:57.624123
31	technitium.php	Cache	technitium.php	Cache		0	2026-09-23 20:21:12.036754
26	technitium.php	Blocking	blocking.php	Blocking		2	2026-09-23 20:06:57.289918
32	technitium.php	Recursion	recursion.php	Recursion		3	2026-09-23 21:05:39.012431
33	network.php	Local Interface	network.php	Network		0	2026-09-23 21:30:59.23017
35	netfortress.php	Reports	netfortress-reports.php	NetFortress		1	2026-09-29 23:01:34.208073
36	netfortress.php	Firewall	netfortress-firewall.php	NetFortress		5	2026-09-29 23:01:34.208073
37	netfortress.php	Devices	netfortress.php	NetFortress		0	2026-09-29 23:01:34.208073
38	netfortress.php	Modules	netfortress-modules.php	NetFortress		6	2026-09-29 23:01:34.208073
39	netfortress.php	Audit Log	netfortress-audit.php	NetFortress		2	2026-09-29 23:01:34.208073
40	netfortress.php	Web Control	netfortress-web-control.php	NetFortress		4	2026-09-29 23:01:34.208073
41	netfortress.php	Blocking	netfortress-blocking.php	NetFortress		3	2026-09-29 23:01:34.208073
42	netfortress.php	Operations	netfortress-operations.php	NetFortress		7	2026-09-29 23:01:34.208073
\.


--
-- Data for Name: permissions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.permissions (id, permission_key, permission_name, parent_id) FROM stdin;
52	general	General	\N
55	security	Security	\N
57	system_status	System Status	\N
62	time_zone	Time Zone	52
63	reports	Reports	52
71	banner	Banner	54
72	logo	Logo	54
74	favicon	Favicon	54
77	login	Login	54
78	https_ssl	HTTPS/SSL	55
81	session_timeout	Session Timeout	55
82	third_party_integrations	3rd Party Integrations	55
83	data_deletion	Data Deletion	55
87	database_server	Database Server	57
88	api_server	API Server	57
89	dns_server_status	DNS Server Status	57
92	customization	Customization	\N
54	appearance	Appearance	92
93	theme	Theme	54
94	sidebar	Sidebar	54
95	user_disclaimer	User Disclaimer	54
98	user_management	User Management	55
79	users	Users	98
80	user_groups	User Groups	98
99	connectivity_status	Connectivity Status	57
100	other_permissions	Other Permissions	\N
58	dashboard	Dashboard	100
59	pending_requests	Pending Requests	100
60	approve_requests	Approve Requests	100
61	deny_requests	Deny Requests	100
91	edit_user_fields	Edit User Fields	100
56	notifications	Communications	\N
84	email_notifications	Email Notifications	101
85	push_notifications	Push Notifications	101
102	whatsapp	WhatsApp	101
103	telegram	Telegram	101
104	edit_settings_fields	Edit Settings Fields	100
105	pushbullet	Pushbullet	101
101	notification_settings	Notification Channels	56
106	monitor_alerts	Monitor Alerts	56
107	login_notification	Notification Channel	106
108	technitium	Technitium	53
69	network_proxy	Network Proxy	108
70	dhcp	DHCP	108
109	cache	Cache	108
64	flush_cache	Flush Cache	109
65	enable_disable_cache	Enable/Disable Cache	109
66	blocking	Blocking	108
110	recursion	Recursion	108
53	dns_server	Services	\N
111	network	Network	53
112	monitor	Monitor	100
114	edit_monitor	Edit Monitor	112
115	view_monitor	View Monitor	112
117	netfortress	NetFortress	53
\.


--
-- Data for Name: portal_auth; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.portal_auth (id, username, password_hash, is_disabled, must_change_password, technitium_synced, migrated_from_technitium, created_at, updated_at, totp_secret, totp_pending_secret, totp_enabled, totp_last_timestep) FROM stdin;
\.


--
-- Data for Name: portal_settings; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.portal_settings (setting_key, setting_value, updated_at) FROM stdin;
default_country_iso	ZA	2026-09-20 17:36:24.407842
monitor_card_background	#1d242a	2026-09-28 17:49:05.895366
monitor_card_opacity	12	2026-09-28 17:49:05.895366
theme_basic_sidebar_profile_background	#142330	2026-09-21 10:17:21.713589
theme_basic_banner_fallback	#18232a	2026-09-21 10:17:21.713589
banner_fit_mode	fit	2026-09-25 09:56:44.706062
monitor_text_color		2026-09-28 17:49:05.895366
login_title	DNS Security Dashboard	2026-09-22 16:26:29.650797
theme_basic_page_background	#111c23	2026-09-21 10:17:21.713589
theme_basic_content_background	#111c23	2026-09-21 10:17:21.713589
theme_basic_text_primary	#ffffff	2026-09-21 10:17:21.713589
theme_basic_text_secondary	#aebbc3	2026-09-21 10:17:21.713589
login_subtitle	Welcome Back	2026-09-22 16:26:29.650797
login_logo_size	163	2026-09-22 16:26:29.650797
login_background_overlay	9	2026-09-22 16:26:29.650797
theme_basic_border	#637681	2026-09-21 10:17:21.713589
login_card_position	left	2026-09-22 16:26:29.650797
theme_basic_accent	#c79a00	2026-09-21 10:17:21.713589
show_logo_login	true	2026-09-22 16:26:29.650797
theme_basic_accent_bright	#ebc100	2026-09-21 10:17:21.713589
theme_basic_success	#237a4b	2026-09-21 10:17:21.713589
theme_basic_warning	#c79a00	2026-09-21 10:17:21.713589
theme_basic_banner_text	#ffffff	2026-09-21 10:17:21.713589
theme_basic_banner_secondary_text	#aebbc3	2026-09-21 10:17:21.713589
theme_basic_banner_accent	#c79a00	2026-09-21 10:17:21.713589
theme_basic_card_background	#18232a	2026-09-21 10:17:21.713589
theme_basic_error	#b83b3b	2026-09-21 10:17:21.713589
theme_basic_sidebar_background_top	#222325	2026-09-21 10:17:21.713589
theme_basic_sidebar_background_bottom	#222325	2026-09-21 10:17:21.713589
theme_basic_sidebar_text	#ffffff	2026-09-21 10:17:21.713589
theme_basic_sidebar_icon	#ffffff	2026-09-21 10:17:21.713589
theme_basic_sidebar_hover	#25333d	2026-09-21 10:17:21.713589
theme_basic_sidebar_active	#a88400	2026-09-21 10:17:21.713589
theme_basic_card_background_alt	#202c34	2026-09-21 10:17:21.713589
show_login_footer	true	2026-09-22 16:26:29.650797
login_footer_text	Please Login	2026-09-22 16:26:29.650797
theme_basic_sidebar_active_text	#ffffff	2026-09-21 10:17:21.713589
theme_basic_sidebar_active_accent	#ebc100	2026-09-21 10:17:21.713589
login_animation_enabled	true	2026-09-22 16:26:29.650797
login_animation_style	cyber	2026-09-22 16:26:29.650797
login_animation_intensity	ultra	2026-09-22 16:26:29.650797
portal_timezone	Africa/Johannesburg	2026-09-22 20:54:02.339373
sidebar_width	260	2026-09-21 17:40:20.735767
sidebar_avatar_size	90	2026-09-21 17:40:20.735767
sidebar_nav_text_size	18	2026-09-21 17:40:20.735767
sidebar_collapse_button_size	45	2026-09-21 17:40:20.735767
sidebar_logo_size	140	2026-09-21 17:40:20.735767
portal_favicon		2026-09-21 13:51:35.467614
show_logo_banner	true	2026-09-21 17:37:27.304931
banner_logo_size	173	2026-09-21 17:37:38.954406
show_logo_sidebar	true	2026-09-21 17:37:46.529432
monitor_card_styles	{"dnsserver":{"title":"                        DNS Server                    ","font":13,"color":"#ffffff","refresh":"normal"},"clock":{"title":"","font":10,"color":"#ffffff","refresh":"normal"},"events":{"title":"                        Live Activity                    ","font":14,"color":"#ffffff","refresh":"normal"},"dnstotals":{"title":"                        DNS Totals                    ","font":12,"color":"#ffffff","refresh":"fast"},"back":{"title":"","font":13,"color":"#ffffff","refresh":"normal"},"logins":{"title":"                        Login Feed                    ","font":13,"color":"#ffffff","refresh":"fast"}}	2026-09-28 17:49:05.895366
theme	basic	2026-09-25 10:32:10.78634
banner_animation_enabled	true	2026-09-21 17:38:22.088779
banner_animation_style	digital_rain	2026-09-21 17:38:22.088779
banner_animation_intensity	ultra	2026-09-21 17:38:22.088779
monitor_background_color	#3e4247	2026-09-28 17:49:05.895366
banner_zoom	500	2026-09-25 09:58:49.628756
notify_email_host	wp2-za1.host-ww.net	2026-09-23 18:35:05.291798
notify_email_port	465	2026-09-23 18:35:05.291798
notify_email_encryption	ssl	2026-09-23 18:35:05.291798
notify_email_from	site@chriscoetzer.co.za	2026-09-23 18:35:05.291798
notify_email_username	site@chriscoetzer.co.za	2026-09-23 18:35:05.291798
notify_email_password	I1A;7DF1][M*{kog54	2026-09-23 18:35:05.291798
banner_position_x	74	2026-09-25 09:59:50.359815
banner_position_y	55	2026-09-25 09:59:50.359815
theme_basic_login_input_border	#d1d5db	2026-09-21 10:17:21.713589
theme_basic_login_button	#c79a00	2026-09-21 10:17:21.713589
theme_basic_login_button_text	#111827	2026-09-21 10:17:21.713589
theme_basic_control_accent	#c79a00	2026-09-21 10:17:21.713589
theme_basic_control_hover	#d4af37	2026-09-21 10:17:21.713589
theme_basic_control_focus	#db9812	2026-09-21 10:17:21.713589
theme_basic_card_border	#637681	2026-09-21 10:17:21.713589
theme_basic_card_text	#ffffff	2026-09-21 10:17:21.713589
theme_basic_input_background	#202c34	2026-09-21 10:17:21.713589
theme_basic_input_background_readonly	#1c272e	2026-09-21 10:17:21.713589
theme_basic_input_text	#ffffff	2026-09-21 10:17:21.713589
theme_basic_input_border	#637681	2026-09-21 10:17:21.713589
theme_basic_input_focus	#db9812	2026-09-21 10:17:21.713589
theme_basic_input_placeholder	#aebbc3	2026-09-21 10:17:21.713589
theme_basic_button_primary	#c79a00	2026-09-21 10:17:21.713589
theme_basic_button_primary_hover	#a88400	2026-09-21 10:17:21.713589
theme_basic_button_primary_text	#111827	2026-09-21 10:17:21.713589
theme_basic_button_secondary	#24313a	2026-09-21 10:17:21.713589
theme_basic_button_secondary_hover	#2b3942	2026-09-21 10:17:21.713589
theme_basic_button_secondary_text	#ffffff	2026-09-21 10:17:21.713589
theme_basic_table_header	#c79a00	2026-09-21 10:17:21.713589
theme_basic_table_row	#18232a	2026-09-21 10:17:21.713589
theme_basic_table_row_alt	#18232a	2026-09-21 10:17:21.713589
theme_basic_table_hover	#18232a	2026-09-21 10:17:21.713589
theme_basic_table_border	#18232a	2026-09-21 10:17:21.713589
theme_basic_table_text	#ffffff	2026-09-21 10:17:21.713589
theme_basic_modal_background	#18232a	2026-09-21 10:17:21.713589
theme_basic_modal_header	#142330	2026-09-21 10:17:21.713589
theme_basic_modal_border	#637681	2026-09-21 10:17:21.713589
theme_basic_modal_text	#ffffff	2026-09-21 10:17:21.713589
theme_basic_login_card_background	#ffffff	2026-09-21 10:17:21.713589
theme_basic_login_text	#111827	2026-09-21 10:17:21.713589
theme_basic_login_secondary_text	#64748b	2026-09-21 10:17:21.713589
theme_basic_login_input_background	#ffffff	2026-09-21 10:17:21.713589
user_disclaimer_enabled	true	2026-09-21 11:58:47.143299
user_disclaimer_title	User Information	2026-09-21 11:58:47.143299
user_disclaimer_text	Create a new user account for the portal and assign the appropriate group and permissions.	2026-09-21 11:58:47.143299
user_disclaimer_checklist	User will be created in the portal\nProfile details will be saved\nGroup permissions will apply\nUser will be able to log in once created	2026-09-21 11:58:47.143299
user_disclaimer_note	Make sure the information is correct before creating the user.	2026-09-21 11:58:47.143299
weather_latitude	-25.8	2026-09-22 21:45:30.386174
weather_longitude	29.4	2026-09-22 21:45:30.386174
notify_pushbullet_token	o.e1zh3yfVPraVKW38DeO4osfJSi6JQt8g	2026-09-23 17:56:22.730989
notify_pushbullet_channel		2026-09-23 17:56:22.730989
monitor_table_color	#d41111	2026-09-28 17:49:05.895366
monitor_table_alt_color	#c80e0e	2026-09-28 17:49:05.895366
monitor_table_grid_color	#bf0d0d	2026-09-28 17:49:05.895366
monitor_table_opacity	100	2026-09-28 17:49:05.895366
monitor_table_grid_enabled	0	2026-09-28 17:49:05.895366
company_logo		2026-09-20 20:49:32.784173
banner_image		2026-09-25 09:56:44.706062
login_background_image		2026-09-21 07:09:06.965128
monitor_background_image		2026-09-28 17:49:05.895366
\.


--
-- Data for Name: requests; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.requests (id, domain, client_ip, reason, requested_at, status, approved_at, denied_at, allowed_until, deny_reason, requested_by, allow_minutes, submitted_by) FROM stdin;
\.


--
-- Data for Name: settings_field_sections; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.settings_field_sections (id, section_name, sort_order, created_at) FROM stdin;
1	General	0	2026-09-22 22:12:45.14321
4	Security	1	2026-09-23 10:10:44.555922
5	Customization	2	2026-09-23 11:29:26.824735
7	Communications	4	2026-09-23 11:29:26.824735
6	Services	3	2026-09-23 11:29:26.824735
8	System Status	5	2026-09-23 11:29:26.824735
\.


--
-- Data for Name: settings_fields; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.settings_fields (id, section_id, field_name, field_href, field_permission, sort_order, created_at) FROM stdin;
1	1	Time Zone	time-zone.php	Time Zone	0	2026-09-22 22:12:45.145377
5	4	HTTPS/SSL	https-ssl.php	HTTPS/SSL	0	2026-09-23 10:10:44.558752
6	4	User Management	users.php	User Management	1	2026-09-23 10:10:44.561513
8	5	Appearance	appearance-logo.php	Appearance	0	2026-09-23 11:29:26.827736
10	8	Connectivity Status	connectivity-status	Connectivity Status	0	2026-09-23 11:29:26.827736
7	4	Session Timeout	timeout.php	Session Timeout	2	2026-09-23 10:10:44.563465
9	7	Notification Channels	notifications-email.php	Notifications	0	2026-09-23 11:29:26.827736
22	7	Monitor Alerts	monitor-login.php	Monitor Alerts	1	2026-09-23 13:35:56.510258
30	6	Technitium	technitium.php	Technitium	0	2026-09-23 20:06:57.08311
31	6	Network	network.php	Network	1	2026-09-23 21:25:24.547488
32	8	Network Services Backend	network-backend-status	System Status	-1	2026-09-29 16:52:03.273863
33	6	NetFortress	netfortress.php	NetFortress	2	2026-09-29 23:01:34.2121
\.


--
-- Data for Name: user_custom_field_sections; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.user_custom_field_sections (id, section_name, sort_order, created_at) FROM stdin;
1	Custom User Fields	10	2026-09-20 14:47:17.604704
\.


--
-- Data for Name: user_custom_field_values; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.user_custom_field_values (user_id, field_id, field_value, updated_at) FROM stdin;
\.


--
-- Data for Name: user_custom_fields; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.user_custom_fields (id, field_name, field_key, field_type, required, sort_order, created_at, section_id, prepend, append) FROM stdin;
8	Employee Number	employee_number	text	f	10	2026-09-20 03:09:43.079246	1	EMP-	\N
\.


--
-- Data for Name: user_groups; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.user_groups (username, group_id) FROM stdin;
portal-api	1
chris	1
admin	1
\.


--
-- Data for Name: user_management_tabs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.user_management_tabs (id, tab_name, tab_href, tab_permission, sort_order, created_at) FROM stdin;
1	Users	users.php	Users	0	2026-09-23 10:49:40.116013
2	User Groups	groups.php	User Groups	1	2026-09-23 10:49:40.119387
\.


--
-- Data for Name: user_profiles; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.user_profiles (id, username, display_name, email_address, country_code, mobile_number, group_id, status, created_at, updated_at, surname, department, photo) FROM stdin;
\.


--
-- Name: groups_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.groups_id_seq', 536, true);


--
-- Name: page_tabs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.page_tabs_id_seq', 42, true);


--
-- Name: permissions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.permissions_id_seq', 117, true);


--
-- Name: portal_auth_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.portal_auth_id_seq', 72, true);


--
-- Name: requests_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.requests_id_seq', 8, true);


--
-- Name: settings_field_sections_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.settings_field_sections_id_seq', 12, true);


--
-- Name: settings_fields_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.settings_fields_id_seq', 33, true);


--
-- Name: user_custom_field_sections_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.user_custom_field_sections_id_seq', 6, true);


--
-- Name: user_custom_fields_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.user_custom_fields_id_seq', 15, true);


--
-- Name: user_management_tabs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.user_management_tabs_id_seq', 13, true);


--
-- Name: user_profiles_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.user_profiles_id_seq', 20, true);


--
-- Name: group_permissions_old group_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_permissions_old
    ADD CONSTRAINT group_permissions_pkey PRIMARY KEY (group_id);


--
-- Name: group_permissions group_permissions_pkey1; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_permissions
    ADD CONSTRAINT group_permissions_pkey1 PRIMARY KEY (group_id, permission_id);


--
-- Name: groups groups_group_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.groups
    ADD CONSTRAINT groups_group_name_key UNIQUE (group_name);


--
-- Name: groups groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.groups
    ADD CONSTRAINT groups_pkey PRIMARY KEY (id);


--
-- Name: page_tabs page_tabs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.page_tabs
    ADD CONSTRAINT page_tabs_pkey PRIMARY KEY (id);


--
-- Name: permissions permissions_permission_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permissions
    ADD CONSTRAINT permissions_permission_key_key UNIQUE (permission_key);


--
-- Name: permissions permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permissions
    ADD CONSTRAINT permissions_pkey PRIMARY KEY (id);


--
-- Name: portal_auth portal_auth_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.portal_auth
    ADD CONSTRAINT portal_auth_pkey PRIMARY KEY (id);


--
-- Name: portal_auth portal_auth_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.portal_auth
    ADD CONSTRAINT portal_auth_username_key UNIQUE (username);


--
-- Name: portal_settings portal_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.portal_settings
    ADD CONSTRAINT portal_settings_pkey PRIMARY KEY (setting_key);


--
-- Name: requests requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.requests
    ADD CONSTRAINT requests_pkey PRIMARY KEY (id);


--
-- Name: settings_field_sections settings_field_sections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.settings_field_sections
    ADD CONSTRAINT settings_field_sections_pkey PRIMARY KEY (id);


--
-- Name: settings_fields settings_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.settings_fields
    ADD CONSTRAINT settings_fields_pkey PRIMARY KEY (id);


--
-- Name: user_custom_field_sections user_custom_field_sections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_custom_field_sections
    ADD CONSTRAINT user_custom_field_sections_pkey PRIMARY KEY (id);


--
-- Name: user_custom_field_values user_custom_field_values_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_custom_field_values
    ADD CONSTRAINT user_custom_field_values_pkey PRIMARY KEY (user_id, field_id);


--
-- Name: user_custom_fields user_custom_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_custom_fields
    ADD CONSTRAINT user_custom_fields_pkey PRIMARY KEY (id);


--
-- Name: user_groups user_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_groups
    ADD CONSTRAINT user_groups_pkey PRIMARY KEY (username);


--
-- Name: user_management_tabs user_management_tabs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_management_tabs
    ADD CONSTRAINT user_management_tabs_pkey PRIMARY KEY (id);


--
-- Name: user_profiles user_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_profiles
    ADD CONSTRAINT user_profiles_pkey PRIMARY KEY (id);


--
-- Name: user_profiles user_profiles_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_profiles
    ADD CONSTRAINT user_profiles_username_key UNIQUE (username);


--
-- Name: portal_auth_username_lower_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX portal_auth_username_lower_key ON public.portal_auth USING btree (lower((username)::text));


--
-- Name: settings_field_sections_name_lower_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX settings_field_sections_name_lower_unique ON public.settings_field_sections USING btree (lower((section_name)::text));


--
-- Name: user_custom_field_sections_name_lower_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_custom_field_sections_name_lower_unique ON public.user_custom_field_sections USING btree (lower((section_name)::text));


--
-- Name: user_custom_fields_field_key_lower_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_custom_fields_field_key_lower_unique ON public.user_custom_fields USING btree (lower((field_key)::text));


--
-- Name: user_custom_fields_section_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_custom_fields_section_id_idx ON public.user_custom_fields USING btree (section_id);


--
-- Name: user_profiles_username_lower_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_profiles_username_lower_unique ON public.user_profiles USING btree (lower((username)::text));


--
-- Name: group_permissions fk_gp_group; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_permissions
    ADD CONSTRAINT fk_gp_group FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE CASCADE;


--
-- Name: group_permissions fk_gp_permission; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_permissions
    ADD CONSTRAINT fk_gp_permission FOREIGN KEY (permission_id) REFERENCES public.permissions(id) ON DELETE CASCADE;


--
-- Name: group_permissions_old fk_group_permissions; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_permissions_old
    ADD CONSTRAINT fk_group_permissions FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE CASCADE;


--
-- Name: permissions fk_permissions_parent; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permissions
    ADD CONSTRAINT fk_permissions_parent FOREIGN KEY (parent_id) REFERENCES public.permissions(id) ON DELETE CASCADE;


--
-- Name: user_groups fk_user_groups; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_groups
    ADD CONSTRAINT fk_user_groups FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE CASCADE;


--
-- Name: settings_fields settings_fields_section_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.settings_fields
    ADD CONSTRAINT settings_fields_section_id_fkey FOREIGN KEY (section_id) REFERENCES public.settings_field_sections(id) ON DELETE CASCADE;


--
-- Name: user_custom_field_values user_custom_field_values_field_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_custom_field_values
    ADD CONSTRAINT user_custom_field_values_field_fk FOREIGN KEY (field_id) REFERENCES public.user_custom_fields(id) ON DELETE CASCADE;


--
-- Name: user_custom_field_values user_custom_field_values_user_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_custom_field_values
    ADD CONSTRAINT user_custom_field_values_user_fk FOREIGN KEY (user_id) REFERENCES public.user_profiles(id) ON DELETE CASCADE;


--
-- Name: user_custom_fields user_custom_fields_section_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_custom_fields
    ADD CONSTRAINT user_custom_fields_section_fk FOREIGN KEY (section_id) REFERENCES public.user_custom_field_sections(id) ON DELETE RESTRICT;


--
-- PostgreSQL database dump complete
--

\unrestrict yfsenuV7nGZy2heOQ6Ec9ALJmjNSThE3Nei882eunnzTod4jMOEE4z26R9EESpL

