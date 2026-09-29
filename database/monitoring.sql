--
-- PostgreSQL database dump
--

\restrict zGj5RaGZ1Qn5kNOvKChH19DQn8EnzJbHkgfDbyla2K7D5HCqHYn2aJdscoUHH31

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

--
-- Name: monitoring; Type: SCHEMA; Schema: -; Owner: monitoring_user
--

CREATE SCHEMA monitoring;


ALTER SCHEMA monitoring OWNER TO monitoring_user;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: alerts; Type: TABLE; Schema: monitoring; Owner: monitoring_user
--

CREATE TABLE monitoring.alerts (
    id bigint NOT NULL,
    server_id integer,
    severity character varying(20) NOT NULL,
    title character varying(255) NOT NULL,
    message text,
    alert_status character varying(20) DEFAULT 'active'::character varying,
    acknowledged boolean DEFAULT false,
    acknowledged_at timestamp without time zone,
    resolved_at timestamp without time zone,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE monitoring.alerts OWNER TO monitoring_user;

--
-- Name: alerts_id_seq; Type: SEQUENCE; Schema: monitoring; Owner: monitoring_user
--

CREATE SEQUENCE monitoring.alerts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE monitoring.alerts_id_seq OWNER TO monitoring_user;

--
-- Name: alerts_id_seq; Type: SEQUENCE OWNED BY; Schema: monitoring; Owner: monitoring_user
--

ALTER SEQUENCE monitoring.alerts_id_seq OWNED BY monitoring.alerts.id;


--
-- Name: login_events; Type: TABLE; Schema: monitoring; Owner: postgres
--

CREATE TABLE monitoring.login_events (
    id bigint NOT NULL,
    username text NOT NULL,
    event text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    source_ip text
);


ALTER TABLE monitoring.login_events OWNER TO postgres;

--
-- Name: login_events_id_seq; Type: SEQUENCE; Schema: monitoring; Owner: postgres
--

CREATE SEQUENCE monitoring.login_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE monitoring.login_events_id_seq OWNER TO postgres;

--
-- Name: login_events_id_seq; Type: SEQUENCE OWNED BY; Schema: monitoring; Owner: postgres
--

ALTER SEQUENCE monitoring.login_events_id_seq OWNED BY monitoring.login_events.id;


--
-- Name: login_notification_rules; Type: TABLE; Schema: monitoring; Owner: monitoring_user
--

CREATE TABLE monitoring.login_notification_rules (
    id integer NOT NULL,
    notification_channel character varying(50) NOT NULL,
    notification_type character varying(50) NOT NULL,
    target_username character varying(255) NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    login_custom_message text DEFAULT ''::text NOT NULL,
    logout_custom_message text DEFAULT ''::text NOT NULL,
    failed_custom_message text DEFAULT ''::text NOT NULL,
    rule_function character varying(100) DEFAULT 'Login Notification'::character varying NOT NULL
);


ALTER TABLE monitoring.login_notification_rules OWNER TO monitoring_user;

--
-- Name: login_notification_rules_id_seq; Type: SEQUENCE; Schema: monitoring; Owner: monitoring_user
--

CREATE SEQUENCE monitoring.login_notification_rules_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE monitoring.login_notification_rules_id_seq OWNER TO monitoring_user;

--
-- Name: login_notification_rules_id_seq; Type: SEQUENCE OWNED BY; Schema: monitoring; Owner: monitoring_user
--

ALTER SEQUENCE monitoring.login_notification_rules_id_seq OWNED BY monitoring.login_notification_rules.id;


--
-- Name: metrics; Type: TABLE; Schema: monitoring; Owner: monitoring_user
--

CREATE TABLE monitoring.metrics (
    id bigint NOT NULL,
    server_id integer NOT NULL,
    cpu_percent numeric(5,2),
    memory_percent numeric(5,2),
    disk_percent numeric(5,2),
    load_1m numeric(6,2),
    load_5m numeric(6,2),
    load_15m numeric(6,2),
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE monitoring.metrics OWNER TO monitoring_user;

--
-- Name: metrics_id_seq; Type: SEQUENCE; Schema: monitoring; Owner: monitoring_user
--

CREATE SEQUENCE monitoring.metrics_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE monitoring.metrics_id_seq OWNER TO monitoring_user;

--
-- Name: metrics_id_seq; Type: SEQUENCE OWNED BY; Schema: monitoring; Owner: monitoring_user
--

ALTER SEQUENCE monitoring.metrics_id_seq OWNED BY monitoring.metrics.id;


--
-- Name: notifications; Type: TABLE; Schema: monitoring; Owner: monitoring_user
--

CREATE TABLE monitoring.notifications (
    id bigint NOT NULL,
    alert_id bigint,
    channel character varying(50),
    recipient character varying(255),
    delivery_status character varying(20) DEFAULT 'pending'::character varying,
    sent_at timestamp without time zone,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE monitoring.notifications OWNER TO monitoring_user;

--
-- Name: notifications_id_seq; Type: SEQUENCE; Schema: monitoring; Owner: monitoring_user
--

CREATE SEQUENCE monitoring.notifications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE monitoring.notifications_id_seq OWNER TO monitoring_user;

--
-- Name: notifications_id_seq; Type: SEQUENCE OWNED BY; Schema: monitoring; Owner: monitoring_user
--

ALTER SEQUENCE monitoring.notifications_id_seq OWNED BY monitoring.notifications.id;


--
-- Name: servers; Type: TABLE; Schema: monitoring; Owner: monitoring_user
--

CREATE TABLE monitoring.servers (
    id integer NOT NULL,
    hostname character varying(255) NOT NULL,
    ip_address character varying(45),
    environment character varying(50),
    status character varying(20) DEFAULT 'online'::character varying,
    last_seen timestamp without time zone,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE monitoring.servers OWNER TO monitoring_user;

--
-- Name: servers_id_seq; Type: SEQUENCE; Schema: monitoring; Owner: monitoring_user
--

CREATE SEQUENCE monitoring.servers_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE monitoring.servers_id_seq OWNER TO monitoring_user;

--
-- Name: servers_id_seq; Type: SEQUENCE OWNED BY; Schema: monitoring; Owner: monitoring_user
--

ALTER SEQUENCE monitoring.servers_id_seq OWNED BY monitoring.servers.id;


--
-- Name: alerts id; Type: DEFAULT; Schema: monitoring; Owner: monitoring_user
--

ALTER TABLE ONLY monitoring.alerts ALTER COLUMN id SET DEFAULT nextval('monitoring.alerts_id_seq'::regclass);


--
-- Name: login_events id; Type: DEFAULT; Schema: monitoring; Owner: postgres
--

ALTER TABLE ONLY monitoring.login_events ALTER COLUMN id SET DEFAULT nextval('monitoring.login_events_id_seq'::regclass);


--
-- Name: login_notification_rules id; Type: DEFAULT; Schema: monitoring; Owner: monitoring_user
--

ALTER TABLE ONLY monitoring.login_notification_rules ALTER COLUMN id SET DEFAULT nextval('monitoring.login_notification_rules_id_seq'::regclass);


--
-- Name: metrics id; Type: DEFAULT; Schema: monitoring; Owner: monitoring_user
--

ALTER TABLE ONLY monitoring.metrics ALTER COLUMN id SET DEFAULT nextval('monitoring.metrics_id_seq'::regclass);


--
-- Name: notifications id; Type: DEFAULT; Schema: monitoring; Owner: monitoring_user
--

ALTER TABLE ONLY monitoring.notifications ALTER COLUMN id SET DEFAULT nextval('monitoring.notifications_id_seq'::regclass);


--
-- Name: servers id; Type: DEFAULT; Schema: monitoring; Owner: monitoring_user
--

ALTER TABLE ONLY monitoring.servers ALTER COLUMN id SET DEFAULT nextval('monitoring.servers_id_seq'::regclass);


--
-- Name: alerts alerts_pkey; Type: CONSTRAINT; Schema: monitoring; Owner: monitoring_user
--

ALTER TABLE ONLY monitoring.alerts
    ADD CONSTRAINT alerts_pkey PRIMARY KEY (id);


--
-- Name: login_events login_events_pkey; Type: CONSTRAINT; Schema: monitoring; Owner: postgres
--

ALTER TABLE ONLY monitoring.login_events
    ADD CONSTRAINT login_events_pkey PRIMARY KEY (id);


--
-- Name: login_notification_rules login_notification_rules_pkey; Type: CONSTRAINT; Schema: monitoring; Owner: monitoring_user
--

ALTER TABLE ONLY monitoring.login_notification_rules
    ADD CONSTRAINT login_notification_rules_pkey PRIMARY KEY (id);


--
-- Name: metrics metrics_pkey; Type: CONSTRAINT; Schema: monitoring; Owner: monitoring_user
--

ALTER TABLE ONLY monitoring.metrics
    ADD CONSTRAINT metrics_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: monitoring; Owner: monitoring_user
--

ALTER TABLE ONLY monitoring.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: servers servers_hostname_key; Type: CONSTRAINT; Schema: monitoring; Owner: monitoring_user
--

ALTER TABLE ONLY monitoring.servers
    ADD CONSTRAINT servers_hostname_key UNIQUE (hostname);


--
-- Name: servers servers_pkey; Type: CONSTRAINT; Schema: monitoring; Owner: monitoring_user
--

ALTER TABLE ONLY monitoring.servers
    ADD CONSTRAINT servers_pkey PRIMARY KEY (id);


--
-- Name: idx_alerts_server; Type: INDEX; Schema: monitoring; Owner: monitoring_user
--

CREATE INDEX idx_alerts_server ON monitoring.alerts USING btree (server_id);


--
-- Name: idx_alerts_status; Type: INDEX; Schema: monitoring; Owner: monitoring_user
--

CREATE INDEX idx_alerts_status ON monitoring.alerts USING btree (alert_status);


--
-- Name: idx_metrics_created; Type: INDEX; Schema: monitoring; Owner: monitoring_user
--

CREATE INDEX idx_metrics_created ON monitoring.metrics USING btree (created_at);


--
-- Name: idx_metrics_server; Type: INDEX; Schema: monitoring; Owner: monitoring_user
--

CREATE INDEX idx_metrics_server ON monitoring.metrics USING btree (server_id);


--
-- Name: alerts alerts_server_id_fkey; Type: FK CONSTRAINT; Schema: monitoring; Owner: monitoring_user
--

ALTER TABLE ONLY monitoring.alerts
    ADD CONSTRAINT alerts_server_id_fkey FOREIGN KEY (server_id) REFERENCES monitoring.servers(id);


--
-- Name: metrics metrics_server_id_fkey; Type: FK CONSTRAINT; Schema: monitoring; Owner: monitoring_user
--

ALTER TABLE ONLY monitoring.metrics
    ADD CONSTRAINT metrics_server_id_fkey FOREIGN KEY (server_id) REFERENCES monitoring.servers(id) ON DELETE CASCADE;


--
-- Name: notifications notifications_alert_id_fkey; Type: FK CONSTRAINT; Schema: monitoring; Owner: monitoring_user
--

ALTER TABLE ONLY monitoring.notifications
    ADD CONSTRAINT notifications_alert_id_fkey FOREIGN KEY (alert_id) REFERENCES monitoring.alerts(id) ON DELETE CASCADE;


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT ALL ON SCHEMA public TO monitoring_user;


--
-- Name: TABLE login_events; Type: ACL; Schema: monitoring; Owner: postgres
--

GRANT ALL ON TABLE monitoring.login_events TO monitoring_user;


--
-- Name: SEQUENCE login_events_id_seq; Type: ACL; Schema: monitoring; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE monitoring.login_events_id_seq TO monitoring_user;


--
-- PostgreSQL database dump complete
--

\unrestrict zGj5RaGZ1Qn5kNOvKChH19DQn8EnzJbHkgfDbyla2K7D5HCqHYn2aJdscoUHH31

