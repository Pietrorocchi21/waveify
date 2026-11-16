# Backend gratuito e trasferibile

Decisione: conservare Supabase (PostgreSQL, Auth, Storage, Realtime), usando
migrazioni SQL nel repository, libreria locale sempre disponibile e backup
indipendenti dal progetto. Nessun servizio a pagamento viene attivato dal codice.
Il piano Free ha limiti di spazio, traffico, email e inattività: non equivale a
risorse illimitate. Il piano effettivo va verificato nel Dashboard Supabase.

Il sistema attuale usa snapshot JSON con controllo di revisione atomico. Li
manteniamo per compatibilità con l'EXE già verificato. La normalizzazione completa
è una possibile evoluzione; ricostruire tutte le tabelle a ogni evento audio
aggiungerebbe lavoro e consumi senza aiutare l'uso personale iniziale.

## Attivazione

Nel repository GitHub, Settings → Secrets and variables → Actions, aggiungere
**un solo accesso amministrativo**:

- `SUPABASE_ACCESS_TOKEN`: token personale Supabase, oppure
- `WAVEIFY_DATABASE_URL`: URL PostgreSQL del progetto (session pooler supportato).

I token si inseriscono nei GitHub Secrets, mai in chat, nei workflow o nell'EXE.
Il connettore GitHub attuale non può creare questi secret. La publishable key
serve al client e non permette di installare tabelle o policy.

Avviare il workflow **Waveify backend** sul branch del progetto:
`status` verifica configurazione; `deploy` installa le sole migrazioni Waveify
0004 e successive in una transazione, senza applicare le vecchie migrazioni
legacy. Un registro privato con checksum impedisce riesecuzioni accidentali e
rileva modifiche a migrazioni già installate. Non modificare file già applicati:
aggiungere una nuova migrazione.

In alternativa, `supabase/bootstrap.sql` è pronto per il SQL Editor Supabase.
Contiene gli stessi controlli e lo stesso registro delle migrazioni automatiche.
Se le migrazioni erano state applicate manualmente prima di questo registro,
non forzare il deploy: riconciliare lo schema e la cronologia prima di procedere.

## Backup e trasferimento

Il comando `backup` esporta librerie, relazioni follow, elenco delle identità
(senza password o token) e tutti i file del bucket privato. Include conteggio,
checksum SHA-256 e migrazioni nel manifest. Le proiezioni pubbliche si rigenerano
dalle librerie; i comandi remoti effimeri non vengono esportati.

Per un backup completo dei file, serve anche `SUPABASE_SERVICE_ROLE_KEY` nei
GitHub Secrets, oppure il token amministrativo Supabase che permette di ottenere
la chiave server al momento dell'operazione. Questa chiave resta solo sul runner.
Il comando interrompe l'esportazione se ci sono file ma manca l'accesso.

Impostare inoltre `WAVEIFY_BACKUP_PASSPHRASE` (almeno 20 caratteri, conservata in
un gestore password). Il workflow carica **solo il backup cifrato** AES-256-GCM,
con chiave derivata tramite scrypt e verifica di integrità per ogni blocco.
I backup si avviano manualmente, scadono dopo 7 giorni negli artifact GitHub e
vanno scaricati e conservati altrove. Nessun cron consuma traffico in automatico.
Il download dei propri audio usa la quota di trasferimento Supabase.

Da terminale (Python 3.12+, `pip install -r tool/backend/requirements.txt`):

```
python -m tool.backend.manage status
python -m tool.backend.manage deploy
python -m tool.backend.manage backup --output waveify-backup.wfy
python -m tool.backend.manage inspect --archive waveify-backup.wfy
python -m tool.backend.manage restore --archive waveify-backup.wfy --identity-map identities.json
```

Configurazione via variabili d'ambiente:
`SUPABASE_URL`, uno degli accessi amministrativi sopra,
e per backup/ripristino `WAVEIFY_BACKUP_PASSPHRASE`.
`SUPABASE_SERVICE_ROLE_KEY` serve ai file quando non è presente un token management.
Il ripristino è un comando locale esplicito, non un job automatico.

Sul nuovo progetto: applicare le migrazioni, creare gli account desiderati e
fornire una mappa JSON `{"UUID_VECCHIO":"UUID_NUOVO"}`. Non vengono esportate
password: gli utenti effettuano nuovamente l'accesso con le nuove credenziali.
Il ripristino accetta solo librerie destinazione vuote, riscrive gli ID utente e
le URI `storage://waveify_media/UUID/...`, carica gli oggetti e ripristina i dati
in transazione. Richiede una mappa completa e univoca, verifica che gli account
esistano e non sovrascrive dati presenti. In caso di errore DB elimina i file
appena caricati; in caso di interruzione brutale possono restare file orfani da
rimuovere prima di ripetere. Fermare le modifiche alla libreria durante il backup.

Per migrare a un altro Supabase (anche self-hosted) basta poi ricompilare il
client con il nuovo URL e la nuova chiave pubblica. I backup contengono JSON,
SQL e file originali: si possono importare anche su PostgreSQL e storage diversi,
ma un servizio diverso da Supabase richiede un adattatore per Auth/Storage e
Realtime; cambiare soltanto l'URL non rende compatibile qualunque backend.

## Limiti controllati dall'applicazione

Il bucket è privato; i nuovi caricamenti sono limitati a 25 MiB per file (o al
limite inferiore già configurato). Ogni snapshot cloud è limitato a 16 MiB;
la cronologia locale conserva gli ultimi 2.000 eventi. Questi limiti riducono i
consumi ma non sostituiscono le quote complessive del piano Free. Un upgrade o
un trasferimento futuro richiede una decisione esplicita: il workflow non cambia
abbonamenti, non crea istanze e non attiva fatturazione.
