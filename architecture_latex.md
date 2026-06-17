\section{Architecture}
Pour concevoir une application robuste, maintenable et évolutive, nous avons opté pour une architecture orientée services (SOA) inspirée du modèle MVC (Modèle-Vue-Contrôleur) réactif.

Cette architecture permet de dissocier clairement l'interface utilisateur, la logique métier de l'application et la structuration des données. Dans le contexte de notre application mobile développée avec Flutter et de notre backend avec FastAPI, les trois composants se structurent de la manière suivante :

\begin{itemize}[label=$\bullet$]
    \item\textbf{Modèles (Model) : } Ils décrivent les entités métiers indispensables au système de réservation et de suivi en temps réel (utilisateurs, conducteurs, trajets). Responsables de l'encapsulation des données au sein du dossier \texttt{lib/models/}, ils intègrent les mécanismes de sérialisation et de désérialisation JSON nécessaires pour valider et structurer de manière cohérente les flux de données échangés avec l'API FastAPI.
    \vspace{4mm}
    \item\textbf{Vues (View) : } Elles constituent l'interface graphique utilisateur développée avec les widgets réactifs de Flutter. Structurées dans les répertoires \texttt{lib/screens/} (organisées par rôles d'utilisateurs et d'authentification) et \texttt{lib/widgets/}, elles affichent dynamiquement les informations provenant des modèles et capturent les actions de l'utilisateur. Elles se reconstruisent de façon ciblée et automatique grâce à un paradigme déclaratif réactif.
    \vspace{4mm}
    \item\textbf{Contrôleurs / Services (Controller) : } Représentés par la couche des services sous le dossier \texttt{lib/services/}, ils centralisent toute la logique métier globale et la gestion de l'état de l'application. Ils orchestrent la communication avec le backend via des requêtes HTTP (REST) et des connexions WebSockets en temps réel, écoutent les notifications push via Firebase (FCM), et gèrent les capteurs matériels comme la géolocalisation GPS. La liaison dynamique et réactive entre ces contrôleurs et les vues est assurée par le package \texttt{provider}.
\end{itemize}
\vspace{4mm}

\begin{figure}[H]
  \centering
  \includegraphics[scale=0.45]{cover/figuresChap4/architecture_smartpickup.png}
  \caption{Schéma d'architecture réactive (Modèle-Vue-Service) adapté à SmartPickup}
  \label{fig:architecture_smartpickup}
\end{figure}

---

### Visualisation de la Figure Générée :

![Schéma d'architecture SmartPickup](C:\Users\tayssir\.gemini\antigravity\brain\be0510a3-9960-45d1-b9b8-e7305a5927dd\smartpickup_architecture_1779136411729.png)
